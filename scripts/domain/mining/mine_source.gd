class_name MineSource
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")

var source_id := ""
var mineral_id := ""
var display_name := ""
var item_definition_id := ""
var world_presentation_id := ""
var map_instance_id := ""
var position := Vector2.ZERO
var capacity := 0
var remaining := 0
var required_mining_level := 0
var experience_coefficient := 1.0
var visual_variant := 0
var alpha_byte := 255


## 用可信目录定义创建一个服务端矿源聚合。
func configure(definition: Dictionary) -> DomainResult:
	if definition.is_empty():
		return DomainResult.failure(&"mining.invalid_source", "mine source definition is empty")
	source_id = String(definition.get("source_id", ""))
	mineral_id = String(definition.get("mineral_id", ""))
	display_name = String(definition.get("display_name", ""))
	item_definition_id = String(definition.get("item_definition_id", ""))
	world_presentation_id = String(definition.get("world_presentation_id", ""))
	map_instance_id = String(definition.get("map_instance_id", ""))
	position = Vector2(definition.get("position", Vector2.INF))
	capacity = int(definition.get("capacity", 0))
	remaining = int(definition.get("remaining", capacity))
	required_mining_level = int(definition.get("required_mining_level", -1))
	experience_coefficient = float(definition.get("experience_coefficient", 0.0))
	visual_variant = int(definition.get("visual_variant", 0))
	alpha_byte = int(definition.get("alpha_byte", 255))
	if source_id.is_empty() or mineral_id.is_empty() or item_definition_id.is_empty() \
			or map_instance_id.is_empty() or not position.is_finite() or capacity <= 0 \
			or remaining <= 0 or remaining > capacity or required_mining_level < 0 \
			or not is_finite(experience_coefficient) or experience_coefficient <= 0.0 \
			or visual_variant < 0 or alpha_byte < 0 or alpha_byte > 255:
		return DomainResult.failure(&"mining.invalid_source", "mine source fields are invalid")
	return DomainResult.ok(self)


## 结算已经完成背包事务的一次采集；矿源不会出现负储量。
func extract(quantity: int) -> DomainResult:
	if quantity <= 0 or quantity > remaining:
		return DomainResult.failure(&"mining.invalid_yield", "mine extraction exceeds remaining content")
	remaining -= quantity
	return DomainResult.ok(remaining)


## 导出客户端只读快照；剩余量不会改变荣耀版矿源外观。
func snapshot() -> Dictionary:
	return {
		"source_id": source_id,
		"mineral_id": mineral_id,
		"display_name": display_name,
		"position": [position.x, position.y],
		"remaining": remaining,
		"capacity": capacity,
		"required_mining_level": required_mining_level,
		"world_presentation_id": world_presentation_id,
		"visual_variant": visual_variant,
		"alpha": float(alpha_byte) / 255.0,
	}
