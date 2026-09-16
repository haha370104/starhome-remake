class_name RewardPolicyLoader
extends RefCounted

const DEFAULT_PATH := "res://data/gameplay/reward_modifiers_v1.json"
static var _default_result: DomainResult


## 装载只读运营规则并缓存，客户端命令不能替换该配置。
## 返回统一切面或配置错误；修改文件后重启服务端生效。
static func load_default() -> DomainResult:
	if _default_result == null:
		var loaded := JsonConfigLoader.load_dictionary(DEFAULT_PATH)
		_default_result = from_document(loaded.value) if loaded.is_ok else loaded
	return _default_result


## 在JSON边界将运营规则转换为领域对象。
## [param document] 服务端策略文档，不是玩家状态或RPC请求。
## 返回完成配置的奖励切面，任何无效条目使整份配置失败。
static func from_document(document: Dictionary) -> DomainResult:
	if int(document.get("schema_version", 0)) != 1 or not document.get("rules") is Array:
		return DomainResult.failure(&"reward.invalid_policy", "奖励策略格式错误")
	var rules: Array[RewardModifier] = []
	var seen := {}
	for raw: Variant in document.rules:
		if not raw is Dictionary:
			return DomainResult.failure(&"reward.invalid_policy", "规则必须是对象")
		var parsed := RewardModifier.parse(raw)
		if not parsed.is_ok:
			return parsed
		var rule: RewardModifier = parsed.value
		if seen.has(rule.id):
			return DomainResult.failure(&"reward.duplicate_rule", "规则标识重复")
		seen[rule.id] = true
		rules.append(rule)
	var pipeline := RewardPipeline.new()
	pipeline.add_provider(RewardModifierProvider.new(rules))
	return DomainResult.ok(pipeline)
