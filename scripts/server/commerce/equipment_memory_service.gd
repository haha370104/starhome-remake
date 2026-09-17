class_name EquipmentMemoryService
extends RefCounted

const COMMANDS := ["query_equipment_memory", "process_equipment_memory", "buy_equipment_memory_item"]
var _items: ItemCatalog
var _random := RandomNumberGenerator.new()


## 注入权威目录与随机源。
## [param items] 同一物品目录。
func _init(items: ItemCatalog) -> void:
	_items = items
	_random.randomize()


## 分派查询、提取转移和购买，成长载荷始终来自玩家库存。
## [param player] 隔离事务玩家。
## [param command] 客户端意图。
## 返回原子领域结果。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var id := String(command.get("instance_id", ""))
	var material_id := String(command.get("material_id", ""))
	var mode := String(command.get("mode", "extract"))
	var stabilized: bool = command.get("use_stabilizer", false) == true
	var result: DomainResult
	match action:
		"query_equipment_memory": result = DomainResult.ok({})
		"process_equipment_memory":
			result = PlayerEquipmentMemoryActions.execute(player, _items, id, material_id, mode, stabilized,
				int(command.get("inventory_revision", -1)), command.get("confirm_transfer", false) == true, _random.randf())
		"buy_equipment_memory_item":
			var definition_id := String(command.get("definition_id", ""))
			var definition := _items.definition(definition_id)
			var count := int(command.get("quantity", 1))
			if definition.get("kind", "") not in ["equipment_memory_module", "equipment_memory_stabilizer"] or count < 1 or count > mini(99, int(definition.get("max_stack", 1))):
				return DomainResult.failure(&"memory.offer", "请选择记忆模块或稳压剂；模块每次限购一个")
			var created := _items.create(definition_id, {"instance_id": "memory." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": count})
			if not created.is_ok: return created
			result = PlayerWorkshopPurchases.purchase(player, created.value, int(definition.workshop_unit_price), int(command.get("inventory_revision", -1)))
		_:
			return DomainResult.failure(&"memory.command", "未知记忆模块操作")
	if result.is_ok: result.value.merge({"action": action, "instance_id": id, "material_id": material_id, "mode": mode, "use_stabilizer": stabilized}, true)
	return result


## 展示当前模块载荷、原版概率和复刻保护，网络不携带候选对象。
## [param player] 已提交玩家。
## [param operation] 操作及选择事实。
## 返回安全界面快照。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	for id: String in _items.definition_ids():
		var definition := _items.definition(id)
		if definition.get("kind", "") in ["equipment_memory_module", "equipment_memory_stabilizer"]:
			offers.append({"definition_id": id, "display_name": _items.display_name(id), "unit_price": int(definition.workshop_unit_price), "max_quantity": int(definition.max_stack)})
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.vehicle.loadout.items())
	for item: GameItem in all_items:
		var row := item.to_view_dictionary()
		row["presentation"] = item.presentation_for("inventory")
		if item is VehicleEquipment and item.memory_profile != null:
			row["installed"] = player.inventory.find(item.instance_id) == null
			row["attribute_summary"] = "装备需求等级 %d\n只移动所选类型，其他成长保留" % item.memory_profile.level
			equipment.append(row)
		elif item is EquipmentMemoryModule:
			row["attribute_summary"] = EquipmentMemoryDescription.describe(item.memory, _items)
			row.display_name = ("[已载入] " if item.memory.has_growth() else "[空白] ") + String(row.display_name)
			materials.append(row)
	var id := String(operation.get("instance_id", ""))
	var material_id := String(operation.get("material_id", ""))
	var mode := String(operation.get("mode", "extract"))
	var stabilized: bool = operation.get("use_stabilizer", false) == true
	var quote := PlayerEquipmentMemoryActions.preview(player, _items, id, material_id, mode, stabilized)
	var preview := {"can_execute": false, "text": quote.error_message}
	if quote.is_ok:
		preview = quote.value.duplicate()
		var candidate: EquipmentMemoryTransfer.Candidate = preview.candidate
		preview.erase("candidate")
		var module: EquipmentMemoryModule = player.inventory.find(material_id)
		var memory := candidate.module.memory if mode == "extract" else module.memory
		var lines := PackedStringArray([EquipmentMemoryDescription.describe(memory, _items), "\n成功率：%d%%" % roundi(float(preview.chance) * 100)])
		if mode == "extract": lines.append("成功：所选成长移入模块，原装备保留。\n失败：空白模块消失，原装备完全不变。")
		else: lines.append("成功：模块成长写入目标，模块消失。\n失败：模块及其中成长消失，目标不变。\n目标必须没有同类成长，超上限时拒绝。")
		lines.append("未选择的加工、孔槽及晶石都保留。\n失败处理和禁止覆盖为复刻规则。")
		lines.append("电磁稳压剂 ×1（持有 %d）" % player.inventory.count_consumable_definition(PlayerEquipmentMemoryActions.STABILIZER) if stabilized else "未使用稳压剂；勾选后成功率100%。")
		if not preview.can_execute: lines.append(String(preview.reason))
		preview["text"] = "\n".join(lines)
	return {"equipment": equipment, "materials": materials, "offers": offers, "preview": preview,
		"currency": player.inventory.currency, "operation": operation.duplicate(true)}
