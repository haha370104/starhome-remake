class_name ClothingEnhancementService
extends RefCounted

const COMMANDS := ["query_clothing_enhancement", "enhance_clothing", "synthesize_enhancement", "transfer_clothing_gems", "reset_clothing_gems"]
var _items: ItemCatalog


## 复用权威物品目录，不接收客户端提供的品质、价格或产物定义。
## [param items] 已初始化的物品目录。
func _init(items: ItemCatalog) -> void:
	_items = items


## 将不可信操作意图分派给人物装备领域用例。
## [param player] 外层事务还原的隔离玩家聚合。
## [param command] 仅采用操作类型、实例身份及版本。
## 返回领域结果或查询所需的选择身份。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var id := String(command.get("instance_id", ""))
	var stone_id := String(command.get("stone_id", ""))
	var inventory_revision := int(command.get("inventory_revision", -1))
	var state_revision := int(command.get("state_revision", -1))
	var result: DomainResult
	match action:
		"query_clothing_enhancement":
			result = DomainResult.ok({"action": action})
		"enhance_clothing":
			result = PlayerEnhancementActions.enhance(player, id, stone_id, inventory_revision, state_revision)
		"synthesize_enhancement":
			var stone := player.inventory.find(stone_id) as EnhancementStone
			if stone == null or stone.next_definition_id().is_empty():
				return DomainResult.failure(&"enhancement.synthesis", "该材料不能继续合成")
			var created := _items.create(stone.next_definition_id(), {
				"instance_id": "enhancement.%s.%d.%d.%s" % [player.entity_id, player.revision, player.inventory.revision, stone.effect],
				"quantity": 1, "footprint_px": [36, 36]})
			if not created.is_ok:
				return created
			result = PlayerEnhancementActions.synthesize(player, stone, created.value, inventory_revision, state_revision)
		"transfer_clothing_gems":
			result = PlayerEnhancementActions.transfer(player, String(command.get("source_id", "")), id, inventory_revision, state_revision)
		"reset_clothing_gems":
			result = PlayerEnhancementActions.reset(player, id, inventory_revision, state_revision)
		_:
			return DomainResult.failure(&"enhancement.command", "未知的人物装备强化操作")
	if result.is_ok:
		result.value["instance_id"] = id
		result.value["stone_id"] = stone_id
	return result


## 提供人物装备和材料清单，以及当前选择的权威预览。
## [param player] 同版本玩家聚合。
## [param operation] 最近一次操作及选择身份。
## 返回只读窗口数据，禁止客户端自行确认扣费。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var clothes: Array[Dictionary] = []
	var stones: Array[Dictionary] = []
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.character_equipment.items())
	for item: GameItem in all_items:
		if item is Clothing:
			var row := item.to_view_dictionary()
			row["installed"] = player.inventory.find(item.instance_id) == null
			row["presentation"] = item.presentation_for("inventory")
			clothes.append(row)
		elif item is EnhancementStone:
			var stone := item as EnhancementStone
			var row := item.to_view_dictionary()
			row["presentation"] = item.presentation_for("inventory")
			row["synthesis_count"] = stone.synthesis_count()
			row["synthesis_price"] = PlayerEnhancementActions.synthesis_price(stone)
			row["can_synthesize"] = not stone.locked and not stone.next_definition_id().is_empty() \
				and player.inventory.count_consumable_definition(stone.definition_id) >= stone.synthesis_count() \
				and player.inventory.currency >= int(row.synthesis_price)
			stones.append(row)
	var selected := PlayerEnhancementActions.clothing(player, String(operation.get("instance_id", "")))
	var material := player.inventory.find(String(operation.get("stone_id", ""))) as EnhancementStone
	var preview := {"can_enhance": false, "reason": "请选择人物装备和强化材料"}
	if selected != null and material != null:
		var checked := selected.enhancement.preview(material)
		preview["reason"] = checked.error_message if not checked.is_ok else ""
		if checked.is_ok:
			preview.merge(checked.value)
			preview["currency_cost"] = PlayerEnhancementActions.enhancement_price(material, selected)
			preview["can_enhance"] = not selected.locked and selected.durability > 0 and player.inventory.currency >= int(preview.currency_cost)
			if not preview.can_enhance:
				preview.reason = "装备已锁定、损坏或星际币不足"
	return {"clothes": clothes, "stones": stones, "currency": player.inventory.currency,
		"preview": preview, "operation": operation.duplicate(true)}
