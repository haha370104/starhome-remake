class_name GroundItemRecord
extends RefCounted

var loot_id: String
var map_instance_id: String
var position: Vector2
var item: InventoryStackRecord


## 使用背包、仓库共用的实例映射保存地面物品全部成长状态。
## [param dropped] 已由领域规则创建的地面物品。
## 返回持久化记录或无法序列化的错误。
static func from_domain(dropped: GroundItem) -> DomainResult:
	var encoded := InventoryStackRecord.from_item(dropped.item, 0)
	if not encoded.is_ok: return encoded
	var record := GroundItemRecord.new()
	record.loot_id = dropped.loot_id
	record.map_instance_id = dropped.map_instance_id
	record.position = dropped.position
	record.item = encoded.value
	return DomainResult.ok(record)


## 校验存档中的地面身份、位置与完整物品记录。
## [param raw] 数据库地面记录。
## 返回隔离的记录或格式错误。
static func from_dictionary(raw: Variant) -> DomainResult:
	if not raw is Dictionary or not raw.get("position") is Array or raw.position.size() != 2:
		return DomainResult.failure(&"persistence.invalid_ground_item", "地面物品位置无效")
	for coordinate: Variant in raw.position:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
			return DomainResult.failure(&"persistence.invalid_ground_item", "地面物品位置无效")
	var record := GroundItemRecord.new()
	record.loot_id = String(raw.get("loot_id", ""))
	record.map_instance_id = String(raw.get("map_instance_id", ""))
	record.position = Vector2(float(raw.position[0]), float(raw.position[1]))
	var decoded := InventoryStackRecord.from_dictionary(raw.get("item", {}))
	if record.loot_id.is_empty() or record.map_instance_id.is_empty() or not decoded.is_ok:
		return DomainResult.failure(&"persistence.invalid_ground_item", "地面物品身份或实例数据无效")
	record.item = decoded.value
	return DomainResult.ok(record)


## 从稳定物品标识与实例状态恢复充血对象，禁止只按类型重新生成装备。
## [param catalog] 沿用主仓库原物品标识的目录。
## 返回可以执行拾取规则的地面物品。
func to_domain(catalog: ItemCatalog) -> DomainResult:
	var created := catalog.create(item.item_definition_id, item.item_state())
	if not created.is_ok: return created
	var dropped := GroundItem.new()
	dropped.loot_id = loot_id
	dropped.map_instance_id = map_instance_id
	dropped.position = position
	dropped.item = created.value
	return DomainResult.ok(dropped)


## 导出与玩家记录同时提交的独立字典。
## 返回可写入 JSON 的持久化表示。
func to_dictionary() -> Dictionary:
	return {"loot_id": loot_id, "map_instance_id": map_instance_id,
		"position": [position.x, position.y], "item": item.to_dictionary()}
