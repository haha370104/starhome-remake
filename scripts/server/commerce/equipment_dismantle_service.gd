class_name EquipmentDismantleService
extends RefCounted

const COMMANDS := ["query_equipment_dismantle", "dismantle_equipment"]
var _items: ItemCatalog
var _random := RandomNumberGenerator.new()


## 注入已校验的规则和物品工厂。
## [param items] 权威目录。
func _init(items: ItemCatalog) -> void:
	_items = items
	_random.randomize()


## 解析客户端选择，概率、产物与交易身份仅由服务器确定。
## [param player] 当前隔离聚合。
## [param command] 不可信意图。
## 返回实际拆解结果或只读查询。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var id := String(command.get("instance_id", ""))
	var result: DomainResult
	match action:
		"query_equipment_dismantle": result = DomainResult.ok({})
		"dismantle_equipment":
			result = PlayerEquipmentDismantleActions.execute(player, _items, id, int(command.get("inventory_revision", -1)),
				command.get("confirm_destruction", false) == true, _random.randf(), "dismantled." + Crypto.new().generate_random_bytes(16).hex_encode())
		_: return DomainResult.failure(&"dismantle.command", "未知拆解操作")
	if result.is_ok: result.value.merge({"action": action, "instance_id": id}, true)
	return result


## 展示所有概率分支、可能材料和成长销毁风险，不向客户端发送可提交候选。
## [param player] 已提交玩家。
## [param operation] 最近操作事实。
## 返回纯字典快照。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.vehicle.loadout.items())
	for item: GameItem in all_items:
		if not item is VehicleEquipment or not item.dismantle_eligible: continue
		var row := item.to_view_dictionary()
		row["installed"] = player.inventory.find(item.instance_id) == null
		row["attribute_summary"] = "当前品质：%s\n最低要求：绿色；装备必须卸下" % EquipmentQuality.LABELS[item.quality.grade]
		row["presentation"] = item.presentation_for("inventory")
		equipment.append(row)
	var id := String(operation.get("instance_id", ""))
	var selected := player.inventory.find(id) as VehicleEquipment
	if selected == null:
		for item: VehicleEquipment in player.vehicle.loadout.items():
			if item.instance_id == id: selected = item
	var profile: EquipmentDismantleRules.Profile = _items.dismantle_rules.profiles.get(selected.definition_id) if selected != null else null
	var lines := PackedStringArray(["费用：%d 星际币" % _items.dismantle_rules.currency_cost,
		"装备及其中全部加工、强化、孔槽和晶石永久消失，不返还成长材料。\n建议先使用记忆模块转移所需成长。\n"])
	var counts: Dictionary[String, int] = {}
	if profile != null:
		for outcome: EquipmentDismantleRules.Outcome in profile.outcomes:
			var names := PackedStringArray()
			for material: Dictionary in outcome.materials:
				var definition_id := String(material.definition_id)
				names.append("%s ×%d" % [_items.display_name(definition_id), int(material.quantity)])
				counts[definition_id] = maxi(counts.get(definition_id, 0), int(material.quantity))
			lines.append("%d%%：%s" % [roundi(outcome.probability * 100), "无材料返还" if names.is_empty() else "、".join(names)])
	for definition_id: String in counts:
		var item: GameItem = _items.create(definition_id, {}).value
		materials.append({"instance_id": definition_id, "display_name": item.display_name, "amount": counts[definition_id],
			"presentation": item.presentation_for("inventory"), "description": "这是最大可能返还数量；实际一次只抽取一档结果。"})
	var quote := PlayerEquipmentDismantleActions.preview(player, _items, id, "preview." + id)
	if not quote.is_ok: lines.append("\n" + quote.error_message)
	lines.append("\n先检查所有结果的背包容量；绑定装备或晶石使产物绑定。")
	var summary := operation.duplicate(true)
	if summary.has("outputs"):
		var received := PackedStringArray()
		for material: Dictionary in summary.outputs:
			received.append("%s ×%d" % [_items.display_name(String(material.definition_id)), int(material.quantity)])
		if not received.is_empty(): summary["message"] += "：" + "、".join(received)
	return {"equipment": equipment, "materials": materials, "offers": [], "currency": player.inventory.currency,
		"preview": {"can_execute": quote.is_ok, "text": "\n".join(lines)}, "operation": summary}
