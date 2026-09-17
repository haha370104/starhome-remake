class_name VehicleLoadoutExchange
extends RefCounted


## 对真实库存和装配进行整体预演，再一次性交换，不通过单件命令制造中间状态。
## [param player] 同一玩家聚合。[param slots] 已验证方案中的实际实例与位置。
## [param inventory_revision] 预期背包版本。[param loadout_revision] 预期装配版本。
## [param in_field] 当前权威地图是否为战斗地图。
## 返回成功或前置失败；失败保持所有原装备对象不变。
static func apply(player: Player, slots: Array, inventory_revision: int, loadout_revision: int, in_field: bool) -> DomainResult:
	var inventory := player.inventory
	var loadout := player.vehicle.loadout
	var checked := inventory.require_revision(inventory_revision)
	if not checked.is_ok: return checked
	checked = loadout.require_revision(loadout_revision)
	if not checked.is_ok: return checked
	var owned: Dictionary[String, GameItem] = {}
	for item: GameItem in inventory.items(): owned[item.instance_id] = item
	for item: VehicleEquipment in loadout.items(): owned[item.instance_id] = item
	var desired: Dictionary[int, VehicleEquipment] = {}
	var selected: Dictionary[String, bool] = {}
	var changed := false
	for row: Dictionary in slots:
		var item: GameItem = owned.get(String(row.instance_id))
		var location := int(row.location)
		if not item is VehicleEquipment or item.definition_id != String(row.definition_id):
			return DomainResult.failure(&"presets.missing", "方案装备不在背包或战车上：%s" % String(row.display_name))
		var equipment := item as VehicleEquipment
		if selected.has(item.instance_id) or desired.has(location) or not equipment.accepts_location(location):
			return DomainResult.failure(&"equipment.location_rejected", "方案存在重复装备或不兼容槽位")
		if loadout.at(location) != item:
			if item.locked: return _locked(item)
			changed = true
		desired[location] = equipment
		selected[item.instance_id] = true
	if not desired.get(0) is VehicleChassis:
		return DomainResult.failure(&"equipment.chassis_required", "方案必须包含战车底盘")
	if in_field and desired[0] != loadout.at(0):
		return DomainResult.failure(&"equipment.chassis_change_forbidden_in_field", "野外不能切换战车底盘，请返回城区")
	var final_items: Array[GameItem] = []
	var layouts: Array[Dictionary] = []
	var positions: Dictionary[String, Vector2i] = {}
	for item: GameItem in inventory.items():
		if selected.has(item.instance_id): continue
		final_items.append(item)
		layouts.append(item.to_layout_dictionary())
	for item: VehicleEquipment in loadout.items():
		if desired.get(item.equipment_location) == item: continue
		if item.locked: return _locked(item)
		changed = true
		if selected.has(item.instance_id): continue
		if final_items.size() >= inventory.capacity:
			return DomainResult.failure(&"inventory.no_space", "背包不足以容纳整套换装卸下的物品")
		var position := InventoryLayout.first_available_position(layouts, item.footprint_px)
		var layout := item.to_layout_dictionary()
		layout.position_px = [position.x, position.y]
		layouts.append(layout)
		positions[item.instance_id] = position
		final_items.append(item)
	if not changed: return DomainResult.failure(&"presets.already_active", "当前已装备此方案")
	checked = InventoryLayout.validate(layouts)
	if not checked.is_ok: return checked
	# 以上全为只读预演；从这里开始没有会失败的领域分支。
	var next_loadout := VehicleLoadout.new(loadout.revision + 1)
	for location: int in desired:
		var item := desired[location]
		item.equipment_location = location
		next_loadout.restore(item)
	for item: GameItem in final_items:
		if positions.has(item.instance_id):
			item.position_px = positions[item.instance_id]
			item.container_id = "main"
			(item as VehicleEquipment).equipment_location = -1
	inventory._items = final_items
	inventory.commit_transfer()
	player.vehicle.loadout = next_loadout
	player.vehicle.reconcile_loadout_state(false)
	return DomainResult.ok()


## 保留具体锁定物品名称，帮助玩家修正方案。
## [param item] 将被移动的锁定物品。
## 返回未发生交换的失败。
static func _locked(item: GameItem) -> DomainResult:
	return DomainResult.failure(&"inventory.item_locked", "方案涉及锁定装备：%s" % item.display_name)
