class_name ExtraAttributeRules
extends RefCounted

const ATTRIBUTES := ["base_attack", "double_damage_chance", "max_health", "armor", "movement_speed", "ammunition_capacity"]

class Channel extends RefCounted:
	var id: String
	var material_id: String
	var attribute: String
	var points: float
	var maximum: int
	var currency: int
	var materials: Array[Dictionary] = []

var channels: Dictionary[String, Channel] = {}
var _profiles: Dictionary[String, PackedStringArray] = {}
var _by_material: Dictionary[String, Channel] = {}
var _bands: Array[Dictionary] = []


## 将原版资格、逐颗增量和失败档位编译为类型化规则。
## [param raw] 版本化目录。
## 返回规则或配置错误。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	if raw.get("schema_version") != 1:
		return DomainResult.failure(&"extra.rules_invalid", "额外属性规则版本无效")
	var rules := ExtraAttributeRules.new()
	for row: Dictionary in raw.get("channels", []):
		var channel := Channel.new()
		channel.id = String(row.get("id", ""))
		channel.material_id = String(row.get("material_id", ""))
		channel.attribute = String(row.get("attribute", ""))
		channel.points = float(row.get("points", 0))
		channel.maximum = int(row.get("maximum", 0))
		channel.currency = int(row.get("currency", -1))
		if channel.id.is_empty() or channel.material_id.is_empty() or channel.attribute not in ATTRIBUTES \
			or not is_finite(channel.points) or channel.points <= 0 or channel.maximum <= 0 or channel.currency < 0 \
			or rules.channels.has(channel.id) or rules._by_material.has(channel.material_id):
			return DomainResult.failure(&"extra.rules_invalid", "额外属性通道无效")
		for cost: Dictionary in row.get("materials", []):
			if String(cost.get("definition_id", "")).is_empty() or int(cost.get("quantity", 0)) <= 0:
				return DomainResult.failure(&"extra.rules_invalid", "额外属性材料无效")
			channel.materials.append(cost.duplicate(true))
		rules.channels[channel.id] = channel
		rules._by_material[channel.material_id] = channel
	for row: Dictionary in raw.get("equipment", []):
		var id := String(row.get("definition_id", ""))
		if id.is_empty() or rules._profiles.has(id):
			return DomainResult.failure(&"extra.rules_invalid", "额外属性装备身份重复")
		var choices := PackedStringArray(row.get("channels", []))
		for channel: String in choices:
			if not rules.channels.has(channel):
				return DomainResult.failure(&"extra.rules_invalid", "额外属性装备通道缺失")
		rules._profiles[id] = choices
	for band: Dictionary in raw.get("success_bands", []):
		var chance := float(band.get("chance", -1))
		if not is_finite(chance) or chance < 0 or chance > 1 or int(band.get("minimum_level", -1)) < 0 or int(band.get("failure_loss", -1)) < 0:
			return DomainResult.failure(&"extra.rules_invalid", "额外属性成功率无效")
		rules._bands.append(band.duplicate(true))
	if rules._bands.is_empty() or int(rules._bands[0].minimum_level) != 0:
		return DomainResult.failure(&"extra.rules_invalid", "额外属性缺少初始成功率")
	return DomainResult.ok(rules)


## 查询装备允许的加工通道，原版显式禁用的装备返回空集合。
## [param definition_id] 装备定义。
## 返回独立通道列表。
func allowed(definition_id: String) -> PackedStringArray:
	return (_profiles.get(definition_id, PackedStringArray()) as PackedStringArray).duplicate()


## 根据材料身份定位萤石或耀石通道。
## [param definition_id] 材料定义。
## 返回通道或 null。
func material(definition_id: String) -> Channel:
	return _by_material.get(definition_id)


## 按当前颗数选择原版成功率及失败退级策略。
## [param level] 当前通道使用颗数。
## 返回独立档位数据。
func success_band(level: int) -> Dictionary:
	var result: Dictionary = _bands[0]
	for band: Dictionary in _bands:
		if level >= int(band.minimum_level): result = band
	return result.duplicate(true)
