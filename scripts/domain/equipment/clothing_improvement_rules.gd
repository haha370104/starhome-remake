class_name ClothingImprovementRules
extends RefCounted

class Channel extends RefCounted:
	var attribute: String
	var label: String
	var increment: float
	var material_id: String

var channels: Dictionary[String, Channel] = {}
var slots: Dictionary[String, String] = {}
var guaranteed_quantities: Array[int] = []


## 读取原版季节时装资格和七种互斥改良方向。
## [param raw] 版本化配置边界。
## 返回类型化规则或具体错误。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	if raw.get("schema_version") != 1 or raw.get("maximum_level") != 100 or raw.get("failure") != "consume_material_keep_level":
		return DomainResult.failure(&"clothing_improvement.rules", "服装改良规则无效")
	var result := ClothingImprovementRules.new()
	for row: Dictionary in raw.get("channels", []):
		var channel := Channel.new()
		channel.attribute = String(row.get("attribute", ""))
		channel.label = String(row.get("label", ""))
		channel.increment = float(row.get("increment", 0))
		channel.material_id = String(row.get("material_id", ""))
		if channel.attribute not in ClothingEnhancement.GEMS or result.channels.has(channel.attribute) or channel.material_id.is_empty() or not is_finite(channel.increment) or channel.increment <= 0:
			return DomainResult.failure(&"clothing_improvement.rules", "服装改良属性无效")
		result.channels[channel.attribute] = channel
	for row: Dictionary in raw.get("equipment", []):
		var id := String(row.get("definition_id", ""))
		var slot := String(row.get("character_slot", ""))
		if id.is_empty() or result.slots.has(id) or slot not in CharacterEquipment.SLOT_ORDER:
			return DomainResult.failure(&"clothing_improvement.rules", "服装改良资格无效")
		result.slots[id] = slot
	for quantity: int in raw.get("guaranteed_quantities", []):
		if quantity != (1 << (result.guaranteed_quantities.size() + 1)):
			return DomainResult.failure(&"clothing_improvement.rules", "服装改良材料阶梯无效")
		result.guaranteed_quantities.append(quantity)
	if result.channels.size() != 7 or result.guaranteed_quantities.size() != 20 or result.slots.is_empty():
		return DomainResult.failure(&"clothing_improvement.rules", "服装改良配置不完整")
	return DomainResult.ok(result)
