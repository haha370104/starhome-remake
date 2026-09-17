class_name ProductionRules
extends RefCounted

var maximum_cycles := 10000
var maximum_speed := 10
var cycle_milliseconds := 2000


## 将版本化生产上限和周期加载为领域规则，不从客户端接收生产时长。
## 返回合法规则或完整拒绝。
static func load_default() -> DomainResult:
	var loaded := JsonConfigLoader.load_dictionary("res://data/gameplay/production_rules_v1.json")
	return from_document(loaded.value) if loaded.is_ok else loaded


## 校验部署配置的类型、范围与版本，不能静默截断小数或接受布尔值。
## [param raw] 配置文档。
## 返回领域规则。
static func from_document(raw: Dictionary) -> DomainResult:
	if not ProductionQueue.valid_integer(raw.get("version"), 1, 1) \
		or not ProductionQueue.valid_integer(raw.get("maximum_cycles"), 1, 10000) \
		or not ProductionQueue.valid_integer(raw.get("maximum_speed"), 1, 10) \
		or not ProductionQueue.valid_integer(raw.get("cycle_milliseconds"), 100, 60000):
		return DomainResult.failure(&"production.rules", "批量生产规则的版本或范围无效")
	var rules := ProductionRules.new()
	rules.maximum_cycles = int(raw.maximum_cycles)
	rules.maximum_speed = int(raw.maximum_speed)
	rules.cycle_milliseconds = int(raw.cycle_milliseconds)
	return DomainResult.ok(rules)
