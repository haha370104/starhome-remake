class_name VehicleSocketService
extends RefCounted

const COMMANDS := ["query_vehicle_sockets", "open_vehicle_socket", "inlay_vehicle_crystal",
	"extract_vehicle_crystal", "expand_vehicle_sockets", "buy_vehicle_workshop_material"]
var _items: ItemCatalog
var _offers: Dictionary[String, int] = {}
var _random := RandomNumberGenerator.new()


## 组装只读规则和商售材料，价格来自服务器物品配置。
## [param items] 已初始化的物品目录。
func _init(items: ItemCatalog) -> void:
	_items = items
	_random.randomize()
	for id: String in items.definition_ids():
		var price := int(items.definition(id).get("workshop_unit_price", 0))
		if price > 0:
			_offers[id] = price


## 将不可信加工意图转换为领域操作；概率、费用、产物均由服务端确定。
## [param player] 外层事务还原的隔离玩家。
## [param command] 实例、孔位、材料和版本意图。
## 返回操作结果或未提交的领域拒绝。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var id := String(command.get("instance_id", ""))
	var material_id := String(command.get("material_id", ""))
	var raw_index: Variant = command.get("socket_index", 0)
	if not (raw_index is int or raw_index is float) or not is_finite(float(raw_index)) \
		or float(raw_index) != floorf(float(raw_index)):
		return DomainResult.failure(&"sockets.invalid_slot", "孔序号必须为整数")
	var index := int(raw_index)
	var revision := int(command.get("inventory_revision", -1))
	var confirmed: bool = command.get("risk_confirmed", false) is bool and command.get("risk_confirmed", false) == true
	var use_hammer: bool = command.get("use_hammer", false) is bool and command.get("use_hammer", false) == true
	var result: DomainResult
	match action:
		"query_vehicle_sockets":
			result = DomainResult.ok({})
		"open_vehicle_socket":
			result = PlayerVehicleSocketActions.open_socket(player, id, material_id, index, revision, _random.randf(), confirmed)
		"inlay_vehicle_crystal":
			result = PlayerVehicleSocketActions.inlay(player, id, material_id, index, revision)
		"extract_vehicle_crystal":
			result = PlayerVehicleSocketActions.extract(player, id, index, use_hammer, confirmed, revision, _items, _new_id())
		"expand_vehicle_sockets":
			result = PlayerVehicleSocketActions.expand(player, id, revision)
		"buy_vehicle_workshop_material":
			var definition_id := String(command.get("definition_id", ""))
			var quantity := int(command.get("quantity", 1))
			if not _offers.has(definition_id) or quantity < 1 or quantity > 99:
				return DomainResult.failure(&"sockets.offer_invalid", "商品或购买数量无效")
			var created := _items.create(definition_id, {"instance_id": _new_id(), "quantity": quantity})
			if not created.is_ok:
				return created
			result = PlayerVehicleSocketActions.purchase(player, created.value, _offers[definition_id], revision)
		_:
			return DomainResult.failure(&"sockets.unknown_command", "未知战车晶石操作")
	if result.is_ok:
		result.value.merge({"action": action, "instance_id": id, "material_id": material_id,
			"socket_index": index, "use_hammer": use_hammer}, true)
	return result


## 投影同版本装备、材料、孔槽与概率；不把查询变成一次交易。
## [param player] 当前权威玩家。
## [param operation] 操作和选中身份。
## 返回窗口需要的只读快照。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.vehicle.loadout.items())
	for item: GameItem in all_items:
		var row := item.to_view_dictionary()
		row["presentation"] = item.presentation_for("inventory")
		if item is VehicleEquipment and _items.socket_rules.profile(item.definition_id) != null:
			row["installed"] = player.inventory.find(item.instance_id) == null
			row["socket_views"] = _socket_views(item)
			equipment.append(row)
		elif item is VehicleCrystal or _items.socket_rules.solvent(item.definition_id) != null \
			or item.definition_id in [_items.socket_rules.hammer_id, _items.socket_rules.expansion_material]:
			materials.append(row)
	for id: String in _offers:
		offers.append({"definition_id": id, "display_name": _items.display_name(id), "unit_price": _offers[id]})
	return {"equipment": equipment, "materials": materials, "offers": offers,
		"currency": player.inventory.currency, "operation": operation.duplicate(true),
		"preview": _preview(player, operation)}


## 复用领域资格和孔状态输出每种可用操作，风险文本固定在服务端。
## [param player] 当前玩家。
## [param operation] 当前选中装备、孔和材料。
## 返回按钮可用性、概率与清晰的后果描述。
func _preview(player: Player, operation: Dictionary) -> Dictionary:
	var preview := {"can_open": false, "can_inlay": false, "can_extract": false,
		"can_expand": false, "text": "请选择背包中的战车装备；已装配装备须先卸下。"}
	var checked := PlayerVehicleSocketActions.target(player, String(operation.get("instance_id", "")), player.inventory.revision)
	if not checked.is_ok:
		preview.text = checked.error_message
		return preview
	var item: VehicleEquipment = checked.value
	var rules := _items.socket_rules
	var profile := rules.profile(item.definition_id)
	var index := int(operation.get("socket_index", 0))
	var slot := item.sockets.slot_at(index)
	var material := player.inventory.find(String(operation.get("material_id", "")))
	var lines := PackedStringArray(["%s\n已开启 %d / 已解锁 %d / 上限 %d" % [item.display_name,
		item.sockets.opened_count(), item.sockets.capacity(), profile.maximum_capacity]])
	preview.can_expand = profile.expansion and item.sockets.capacity() < profile.maximum_capacity \
		and player.inventory.count_consumable_definition(rules.expansion_material) >= rules.expansion_quantity
	if profile.expansion and item.sockets.capacity() < profile.maximum_capacity:
		lines.append("扩孔：消耗 %d 个武装芯片，解锁一个未开启孔。" % rules.expansion_quantity)
	if slot != null:
		lines.append("当前：第 %d 孔" % (index + 1))
		if not slot.opened and material != null and not material.locked:
			var solvent := rules.solvent(material.definition_id)
			var opening := item.sockets.preview_open(index, profile, solvent, rules)
			if opening.is_ok:
				preview.can_open = true
				lines.append("开槽：消耗 %s ×1，成功率 %.1f%%。" % [material.display_name, float(opening.value) * 100.0])
				lines.append({"none": "失败仅消耗材料。", "destroy_equipment": "失败损毁整件装备和全部晶石！",
					"close_last_socket": "失败损失最高编号的已开孔及其中晶石。"}[solvent.failure])
			else:
				lines.append(opening.error_message)
		elif slot.opened and slot.crystal_id.is_empty():
			preview.can_inlay = material is VehicleCrystal and not material.locked
			lines.append("已开空孔：选择一颗战车晶石镶嵌。")
			if preview.can_inlay:
				var spec := rules.crystal(material.definition_id)
				var label := String({"firepower": "能量炮攻击", "health": "生命", "defense": "防御", "guidance": "导弹攻击", "rocket": "火箭攻击", "critical": "能量炮暴击率"}[spec.effect])
				lines.append("镶嵌 %s ×1，保留裂纹和绑定。\n%s +%s" % [material.display_name, label, ("%.1f%%" % (spec.value * 100)) if spec.effect == "critical" else str(spec.value)])
		elif not slot.crystal_id.is_empty():
			var use_hammer := bool(operation.get("use_hammer", false))
			preview.can_extract = not use_hammer or player.inventory.count_consumable_definition(rules.hammer_id) >= 1
			lines.append("%s\n裂纹 %d / 3" % [_items.display_name(slot.crystal_id), slot.cracks])
			lines.append("精密摘取：消耗精密锤头 ×1，不增加裂纹。" if use_hammer else (
				"普通摘取：晶石已有三裂，将永久损毁！" if slot.cracks >= 3 else "普通摘取：晶石返回背包并新增一个裂纹。"))
	lines.append("\n装配后同类仅最高四颗有效，瑕疵与明亮共用名额。\n暴击晶石只增加能量炮 1.5 倍暴击率。")
	preview.text = "\n".join(lines)
	return preview


## 生成跨进程重启不会与旧堆叠冲突的物品身份。
## 返回随机 128 位实例标识。
func _new_id() -> String:
	return "workshop." + Crypto.new().generate_random_bytes(16).hex_encode()


## 将孔中的稳定身份转为可读名称，界面不负责查询游戏规则目录。
## [param item] 已校验的装备。
## 返回按孔序排列的只读显示数据。
func _socket_views(item: VehicleEquipment) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index: int in item.sockets.capacity():
		var slot := item.sockets.slot_at(index)
		rows.append({"opened": slot.opened, "name": "" if slot.crystal_id.is_empty() else _items.display_name(slot.crystal_id), "cracks": slot.cracks})
	return rows
