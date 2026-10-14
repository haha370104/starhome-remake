class_name AiPlayerSettings
extends RefCounted

class ActorSpec extends RefCounted:
	var id := ""
	var goal := "探索当前地图，逐步成长，优先保证生存。"

var provider := "demo"
var endpoint := "https://api.openai.com/v1/responses"
var model := ""
var api_key_env := "STARHOME_AI_API_KEY"
var timeout_seconds := 20.0
var decision_interval_seconds := 10.0
var requests_per_minute := 6
var max_requests_per_session := 120
var max_output_tokens := 1024
var observation_radius := 900.0
var memory_directory := "user://ai_players/memory"
var actors: Array[ActorSpec] = []


## 仅在显式启用后读取本地配置，限制体积且不读取任何默认账号凭据。
## [param path] 用户指定的JSON文件。
## 返回类型化配置或不含配置正文的错误。
static func load_file(path: String) -> DomainResult:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return DomainResult.failure(&"ai.config_missing", "AI配置文件不存在或不可读")
	if file.get_length() > 65536: return DomainResult.failure(&"ai.config_size", "AI配置不能超过64KiB")
	return from_dictionary(JSON.parse_string(file.get_as_text()))


## 校验所有资源预算；密钥只能由指定环境变量提供，不保存到配置对象。
## [param raw] 配置文件解析结果。
## 返回合法配置；错误不会阻止普通游戏启动。
static func from_dictionary(raw: Variant) -> DomainResult:
	if not raw is Dictionary: return _invalid("AI配置必须是JSON对象")
	var allowed := ["provider", "endpoint", "model", "api_key_env", "timeout_seconds",
		"decision_interval_seconds", "requests_per_minute", "max_requests_per_session",
		"max_output_tokens", "observation_radius", "memory_directory", "actors"]
	for key: Variant in raw:
		if key not in allowed: return _invalid("AI配置包含不支持的字段；密钥请使用环境变量")
	var settings := AiPlayerSettings.new()
	for key: String in ["provider", "endpoint", "model", "api_key_env", "memory_directory"]:
		if raw.has(key):
			if not raw[key] is String or raw[key].length() > 1024: return _invalid("AI文本配置无效")
			settings.set(key, raw[key].strip_edges())
	var bounds := {"timeout_seconds": [1, 120], "decision_interval_seconds": [2, 300],
		"requests_per_minute": [1, 60], "max_requests_per_session": [1, 10000],
		"max_output_tokens": [128, 4096], "observation_radius": [100, 1500]}
	for key: String in bounds:
		if not raw.has(key): continue
		var value: Variant = raw[key]
		if not (value is int or value is float) or not is_finite(float(value)) \
				or value < bounds[key][0] or value > bounds[key][1]: return _invalid("AI预算参数超出范围：" + key)
		if key in ["requests_per_minute", "max_requests_per_session", "max_output_tokens"] and value != int(value):
			return _invalid("AI次数和令牌预算必须为整数")
		settings.set(key, value)
	if settings.provider not in ["demo", "responses"]: return _invalid("provider仅支持demo或responses")
	if settings.memory_directory.is_empty() or settings.memory_directory.begins_with("res://"):
		return _invalid("AI记忆目录须在项目资源之外")
	if settings.provider == "responses":
		if settings.model.is_empty(): return _invalid("真实模型需要填写model")
		if RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*$").search(settings.api_key_env) == null:
			return _invalid("api_key_env必须为环境变量名")
		if RegEx.create_from_string("^https://[^/?#@]+(?:/[^?#]*)?$|^http://(?:127\\.0\\.0\\.1|localhost)(?::[0-9]+)?/[^?#]*$").search(settings.endpoint) == null:
			return _invalid("模型地址须使用HTTPS；本机测试可使用localhost HTTP")
	var rows: Variant = raw.get("actors", [])
	if not rows is Array or rows.is_empty() or rows.size() > 8: return _invalid("请配置1至8个AI角色")
	var ids := {}
	for row: Variant in rows:
		if not row is Dictionary: return _invalid("AI角色配置无效")
		for key: Variant in row:
			if key not in ["id", "goal"]: return _invalid("AI角色只支持id和goal")
		if not row.get("id") is String or RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]{0,47}$").search(row.id) == null:
			return _invalid("AI角色id须为不超过48字符的ASCII标识符")
		if ids.has(row.id): return _invalid("AI角色id不能重复")
		var actor := ActorSpec.new()
		actor.id = row.id
		if row.has("goal"):
			if not row.goal is String or row.goal.length() > 600: return _invalid("AI目标说明过长或类型错误")
			actor.goal = row.goal
		settings.actors.append(actor)
		ids[actor.id] = true
	return DomainResult.ok(settings)


## 构造不包含原始配置与凭据的验证错误。
## [param message] 固定的可读原因。
## 返回失败结果。
static func _invalid(message: String) -> DomainResult:
	return DomainResult.failure(&"ai.config_invalid", message)
