class_name PlayerVehicleSocketActions
extends RefCounted


## 加工只接受自有背包装备，避免加工中损毁仍装配的车体。
## [param player] 当前玩家聚合。
## [param id] 目标实例。
## [param expected_revision] 用户确认时的背包版本。
## 返回可加工装备或拒绝原因。
static func target(player: Player, id: String, expected_revision: int) -> DomainResult:
	var checked := player.inventory.require_revision(expected_revision)
	if not checked.is_ok:
		return checked
	var item := player.inventory.find(id) as VehicleEquipment
	if item == null or item.locked or item.durability <= 0 or item.socket_rules == null \
		or item.socket_rules.profile(item.definition_id) == null:
		return DomainResult.failure(&"sockets.equipment_unavailable", "请将有开槽资格的装备卸到背包，并解除锁定；损坏装备须先维护")
	return DomainResult.ok(item)


## 权威随机开槽，先验证全部条件再支付；失败同样消费一份材料。
## [param player] 当前玩家聚合。
## [param id] 背包装备实例。
## [param material_id] 柔解剂堆叠实例。
## [param index] 目标孔。
## [param expected_revision] 确认时背包版本。
## [param roll] 服务端生成的 [0,1) 随机样本。
## [param risk_confirmed] 用户是否确认预览中的损毁/丢孔风险。
## 返回成功、失败及实际损毁结果。
static func open_socket(player: Player, id: String, material_id: String, index: int, expected_revision: int, roll: float, risk_confirmed: bool) -> DomainResult:
	var checked := target(player, id, expected_revision)
	if not checked.is_ok:
		return checked
	var item: VehicleEquipment = checked.value
	var material := player.inventory.find(material_id)
	if material == null or material.locked or not is_finite(roll) or roll < 0 or roll >= 1:
		return DomainResult.failure(&"sockets.material_unavailable", "请选择未锁定的柔解剂")
	var rules := item.socket_rules
	var solvent := rules.solvent(material.definition_id)
	var preview := item.sockets.preview_open(index, rules.profile(item.definition_id), solvent, rules)
	if not preview.is_ok:
		return preview
	if solvent.failure != "none" and preview.value < 1.0 and not risk_confirmed:
		return DomainResult.failure(&"sockets.confirm_risk", "请确认开槽失败的装备损毁或丢孔风险")
	var paid := player.inventory.remove_quantity(material_id, 1)
	if not paid.is_ok:
		return paid
	item.bound = item.bound or material.bound
	var success := roll < float(preview.value)
	var destroyed := item.sockets.settle_open(index, success, solvent.failure)
	if destroyed:
		player.inventory.remove_quantity(id, 1)
	return DomainResult.ok({"success": success, "destroyed_equipment": destroyed,
		"message": "开槽成功" if success else ("开槽失败，装备已损毁" if destroyed else "开槽失败，已按预览消耗材料并结算孔槽")})


## 将一颗普通战车晶石嵌入空孔，支付之前在候选状态中预检。
## [param player] 当前玩家聚合。
## [param id] 背包装备实例。
## [param crystal_id] 材料堆叠实例。
## [param index] 目标孔。
## [param expected_revision] 确认时背包版本。
## 返回镶嵌结果，失败不修改装备或材料。
static func inlay(player: Player, id: String, crystal_id: String, index: int, expected_revision: int) -> DomainResult:
	var checked := target(player, id, expected_revision)
	if not checked.is_ok:
		return checked
	var item: VehicleEquipment = checked.value
	var crystal := player.inventory.find(crystal_id) as VehicleCrystal
	var candidate: VehicleSockets = VehicleSockets.restore(item.sockets.to_dictionary()).value
	var preview := candidate.inlay(index, crystal)
	if not preview.is_ok:
		return preview
	var paid := player.inventory.remove_quantity(crystal_id, 1)
	if not paid.is_ok:
		return paid
	item.sockets = candidate
	item.bound = item.bound or crystal.bound
	return DomainResult.ok({"message": "镶嵌成功；装配后生效，同类最多四颗"})


## 摘取先完成入包容量和材料事务，再清空孔，三裂普通摘取明确销毁晶石。
## [param player] 当前玩家聚合。
## [param id] 背包装备实例。
## [param index] 孔序号。
## [param use_hammer] 是否消费精密锤免新裂纹。
## [param risk_confirmed] 是否确认三裂晶石损毁。
## [param expected_revision] 确认时背包版本。
## [param catalog] 权威物品目录。
## [param product_id] 权威生成的新晶石实例标识。
## 返回摘取结果；满包失败不扣锤、不丢晶石。
static func extract(player: Player, id: String, index: int, use_hammer: bool, risk_confirmed: bool, expected_revision: int, catalog: ItemCatalog, product_id: String) -> DomainResult:
	var checked := target(player, id, expected_revision)
	if not checked.is_ok:
		return checked
	var item: VehicleEquipment = checked.value
	var slot := item.sockets.slot_at(index)
	if slot == null or slot.crystal_id.is_empty():
		return DomainResult.failure(&"sockets.empty_slot", "请选择已有晶石的孔")
	var destroyed := slot.cracks >= item.socket_rules.maximum_cracks and not use_hammer
	if destroyed and not risk_confirmed:
		return DomainResult.failure(&"sockets.confirm_risk", "该晶石已有三裂，普通摘取会损毁，请明确确认")
	if destroyed:
		player.inventory.commit_transfer()
	else:
		var material_id := item.socket_rules.hammer_id
		var requirements: Array[Dictionary] = []
		var bound := item.bound or slot.bound
		if use_hammer:
			requirements.append({"definition_id": material_id, "quantity": 1})
			bound = bound or _has_bound_material(player, material_id)
		var created := catalog.create(slot.crystal_id, {"instance_id": product_id, "quantity": 1,
			"bound": bound, "crystal_cracks": slot.cracks + (0 if use_hammer else 1)})
		if not created.is_ok:
			return created
		var paid := player.inventory.craft_product(requirements, created.value)
		if not paid.is_ok:
			return paid
	item.sockets.clear_crystal(index)
	return DomainResult.ok({"destroyed_crystal": destroyed,
		"message": "晶石已损毁，孔槽保留" if destroyed else "晶石已摘取到背包"})


## 对符合资格的装备解锁一个扩展孔，支付和状态推进为一个聚合操作。
## [param player] 当前玩家聚合。
## [param id] 背包装备实例。
## [param expected_revision] 确认时背包版本。
## 返回新孔数或未付费的拒绝原因。
static func expand(player: Player, id: String, expected_revision: int) -> DomainResult:
	var checked := target(player, id, expected_revision)
	if not checked.is_ok:
		return checked
	var item: VehicleEquipment = checked.value
	var candidate: VehicleSockets = VehicleSockets.restore(item.sockets.to_dictionary()).value
	var preview := candidate.expand(item.socket_rules.profile(item.definition_id))
	if not preview.is_ok:
		return preview
	var material_id := item.socket_rules.expansion_material
	var bound := _has_bound_material(player, material_id)
	var paid := player.inventory.pay_upgrade_cost([{"definition_id": material_id,
		"quantity": item.socket_rules.expansion_quantity}], 0)
	if not paid.is_ok:
		return paid
	item.sockets = candidate
	item.bound = item.bound or bound
	return DomainResult.ok({"message": "已解锁第 %d 孔，请使用柔解剂开启" % candidate.capacity()})


## 购买加工材料，先检查资金与容量，成功入包后扣金币。
## [param player] 当前玩家聚合。
## [param product] 权威目录创建的商品堆叠。
## [param unit_price] 权威商售配置单价。
## [param expected_revision] 确认时背包版本。
## 返回购买结果或原子失败。
static func purchase(player: Player, product: GameItem, unit_price: int, expected_revision: int) -> DomainResult:
	return PlayerWorkshopPurchases.purchase(player, product, unit_price, expected_revision)


## 配方混合堆叠时保守传播绑定，防止用自动选料洗掉绑定。
## [param player] 当前玩家聚合。
## [param definition_id] 材料定义。
## 返回可消费材料中是否有绑定物品。
static func _has_bound_material(player: Player, definition_id: String) -> bool:
	for item: GameItem in player.inventory.items():
		if item.definition_id == definition_id and item.bound and not item.locked:
			return true
	return false
