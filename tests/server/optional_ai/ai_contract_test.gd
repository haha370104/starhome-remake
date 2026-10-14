extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证外部配置、模型参数、角色身份与预算的受限边界。
func _initialize() -> void:
	var valid := {"actors": [{"id": "explorer"}]}
	_check(AiPlayerSettings.from_dictionary(valid).is_ok, "演示模式无需密钥")
	for invalid: Dictionary in [{}, {"actors": [{"id": "../player.1"}]},
		{"actors": [{"id": "a"}, {"id": "a"}]}, {"actors": [{"id": "a"}], "api_key": "must-not-save"},
		{"actors": [{"id": "a"}], "requests_per_minute": 0}, {"actors": [{"id": "a"}], "timeout_seconds": INF}]:
		_check(not AiPlayerSettings.from_dictionary(invalid).is_ok, "拒绝无效身份、凭据或无限预算")
	var remote := valid.duplicate(true)
	remote.merge({"provider": "responses", "model": "user-selected", "endpoint": "https://example.test/v1/responses"})
	_check(AiPlayerSettings.from_dictionary(remote).is_ok, "解析配置本身不读取密钥")
	remote.endpoint = "http://example.test/v1/responses"
	_check(not AiPlayerSettings.from_dictionary(remote).is_ok, "外部提供器必须使用TLS")
	remote.endpoint = "http://127.0.0.1:32101/responses"
	_check(AiPlayerSettings.from_dictionary(remote).is_ok, "本地模拟接口可独立测试")
	_check(AiPlayerAction.parse({"kind": "move", "x": 120, "y": 50}).is_ok, "普通移动行动")
	for invalid: Dictionary in [{"kind": "grant_loot"}, {"kind": "move", "entity_id": "player.1"},
		{"kind": "move", "x": INF}, {"kind": "hunt", "target_id": "monster", "ability_id": "grant_money"},
		{"kind": "panel", "panel_command_json": '{"type":"grant_loot"}'},
		{"kind": "panel", "panel_command_json": '{"type":"use_inventory_item","inventory_revision":100}'},
		{"kind": "panel", "panel_command_json": '{"type":"use_inventory_item","instance_id":{"injected":true}}'}]:
		_check(not AiPlayerAction.parse(invalid).is_ok, "拒绝越权或畸形模型输出")
	_check(AiPlayerAction.parse({"kind": "panel", "panel_command_json": '{"type":"use_inventory_item","instance_id":"own.item"}'}).is_ok,
		"正常物品意图可交权威域继续验证")
	var observation := AiPlayerObservation.new()
	var target := AiPlayerObservation.Target.new()
	target.id = "near"
	observation.targets["hunt"] = [target]
	_check(observation.find("hunt", "near") == target and observation.find("hunt", "remote") == null,
		"只认当前观察中的目标")
	var actor := AiPlayerActor.new()
	for index in 50: actor.remember(DomainResult.ok(), index)
	_check(actor.history.size() == 20 and actor.next_sequence() != actor.next_sequence(), "记忆有界且命令序号不重用")
	print("AI contracts: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 记录受限输入与状态契约断言。
## [param condition] 实际条件。[param message] 预期行为。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
