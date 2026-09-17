class_name EquipmentForgingRules
extends RefCounted

class Channel extends RefCounted:
	var type := 0
	var attribute := ""
	var label := ""
	var step := 1
	var direct_bonus := false
	var expands_processing := true
	var material_id := ""
	var requirements: Array[Dictionary] = []

class Profile extends RefCounted:
	var limits: Dictionary[int, int] = {}

var profiles: Dictionary[String, Profile] = {}
var channels: Dictionary[int, Channel] = {}
var currency_cost := 0
var chances: Array[float] = []


## 加载原版极限扩展与显式复刻步长，拒绝不完整概率和跨类型配置。
## [param raw] 规则文件边界。
## 返回类型化规则或错误。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	var rules := EquipmentForgingRules.new()
	rules.currency_cost = int(raw.get("currency_cost", -1))
	if raw.get("schema_version") != 1 or rules.currency_cost < 0:
		return DomainResult.failure(&"forging.rules", "锻造费用或版本无效")
	for chance: Variant in raw.get("chances", []):
		if not (chance is float or chance is int) or not is_finite(float(chance)) or float(chance) <= 0 or float(chance) > 1:
			return DomainResult.failure(&"forging.rules", "锻造概率无效")
		rules.chances.append(float(chance))
	if rules.chances.size() != 3: return DomainResult.failure(&"forging.rules", "锻造仅允许投入一到三份芯片")
	for row: Dictionary in raw.get("channels", []):
		var channel := Channel.new()
		channel.type = int(row.get("type", 0))
		channel.attribute = String(row.get("attribute", ""))
		channel.label = String(row.get("label", ""))
		channel.step = int(row.get("step", 0))
		channel.direct_bonus = row.get("direct_bonus", false) == true
		channel.expands_processing = row.get("expands_processing", false) == true
		channel.material_id = String(row.get("material_id", ""))
		if channel.type < 1 or channel.type > 8 or rules.channels.has(channel.type) or channel.attribute not in EquipmentProcessing.ATTRIBUTES or channel.step <= 0 or channel.material_id.is_empty():
			return DomainResult.failure(&"forging.rules", "锻造类型或效果无效")
		for cost: Dictionary in row.get("requirements", []):
			if String(cost.get("definition_id", "")).is_empty() or int(cost.get("quantity", 0)) <= 0:
				return DomainResult.failure(&"forging.rules", "锻造材料无效")
			channel.requirements.append(cost.duplicate(true))
		rules.channels[channel.type] = channel
	for row: Dictionary in raw.get("equipment", []):
		var id := String(row.get("definition_id", ""))
		var profile := Profile.new()
		for key: String in row.get("limits", {}):
			var kind := key.to_int()
			var limit := int(row.limits[key])
			if not rules.channels.has(kind) or str(kind) != key or limit <= 0:
				return DomainResult.failure(&"forging.rules", "锻造上限无效")
			profile.limits[kind] = limit
		if id.is_empty() or rules.profiles.has(id) or profile.limits.is_empty():
			return DomainResult.failure(&"forging.rules", "锻造装备资格无效")
		rules.profiles[id] = profile
	return DomainResult.ok(rules)


## 根据芯片定义查找唯一加工方向。
## [param definition_id] 材料定义。
## 返回只读方向或null。
func material(definition_id: String) -> Channel:
	for channel: Channel in channels.values():
		if channel.material_id == definition_id: return channel
	return null
