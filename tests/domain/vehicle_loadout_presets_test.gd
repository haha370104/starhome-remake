extends SceneTree

var catalog := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var mapper: PlayerStateMapper
var checks := 0
var failures: Array[String] = []


## 使用实际目录与完整映射验证四套方案的所有权、原子交换和存档冷却。
func _initialize() -> void:
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok, "初始化目录和存档夹具")
	mapper = PlayerStateMapper.new(catalog)
	_test_exchange()
	_test_rejections()
	_test_persistence_and_commands()
	for failure in failures: push_error(failure)
	print("VEHICLE_PRESETS_%s (%d checks)" % ["OK" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


## 以满背包互换两台引擎，证明没有单件中间容量限制且保留原对象和资源。
func _test_exchange() -> void:
	var player := _player()
	var original := player.vehicle.loadout.at(3)
	original.durability = 123
	original.bound = true
	_check(_capture(player, 0).is_ok, "保存第一套")
	_check(player.equip_vehicle_item("inventory.spare_engine", 3, player.inventory.revision, player.vehicle.loadout.revision).is_ok, "手动装配第二台真实引擎")
	var alternate := player.vehicle.loadout.at(3)
	_check(_capture(player, 1).is_ok, "保存第二套")
	while player.inventory.items().size() < 40:
		player.inventory.add_reward(catalog.create("beginner_engine", {"instance_id": "filler.%d" % player.inventory.items().size()}).value)
	var old_inventory := player.inventory.revision
	var old_loadout := player.vehicle.loadout.revision
	player.vehicle.health = 35
	player.vehicle.reserve_energy = 3456
	player.vehicle.working_energy = 12
	_check(_apply(player, 0, 100).is_ok, "满背包依然整套互换成功")
	_check(player.vehicle.loadout.at(3) == original and player.inventory.find(alternate.instance_id) == alternate, "保留实际物品引用不复制")
	_check(original.durability == 123 and original.bound and alternate.equipment_location == -1, "成长耐久绑定和卸装位置保留")
	_check(player.inventory.items().size() == 40 and player.inventory.revision == old_inventory + 1 \
		and player.vehicle.loadout.revision == old_loadout + 1, "两处版本各只推进一次")
	_check(player.vehicle.health == 35 and player.vehicle.reserve_energy == 3456 and player.vehicle.working_energy == 12, "换装不会补满能源或生命")
	_check(player.vehicle_presets.ready_at == 130, "权威30秒冷却")
	var before := _state(player)
	_check(not _apply(player, 1, 129).is_ok and _state(player) == before, "冷却中不移动也不扣资源")
	_check(_apply(player, 1, 130).is_ok, "到期可切回")
	before = _state(player)
	_check(not _apply(player, 1, 160).is_ok and _state(player) == before, "相同方案不重复换装或推进冷却")
	var json: Variant = JSON.parse_string(JSON.stringify(_state(player)))
	var restored := PlayerStateRecord.from_dictionary(json)
	_check(restored.is_ok, "完整玩家记录JSON往返")
	var reloaded: Player = mapper.to_domain(restored.value).value
	_check(reloaded.vehicle_presets.to_dictionary() == player.vehicle_presets.to_dictionary(), "四套方案和冷却随正式存档保存")
	_check(not _apply(reloaded, 0, 140).is_ok, "重启不能跳过剩余冷却")
	_check(_apply(reloaded, 0, 160).is_ok and reloaded.vehicle.loadout.at(3).durability == 123, "重启后实际实例与状态仍可换回")
	var current := CurrentPlayer.new(catalog)
	var bundle := fixture._service.build_bundle(mapper.to_record(reloaded).value)
	_check(current.apply_bundle(bundle) and current.vehicle_presets.to_dictionary() == reloaded.vehicle_presets.to_dictionary(), "客户端唯一投影还原同一方案")
	var clone: PlayerStateRecord = restored.value.duplicate_record()
	clone.vehicle_presets.ready_at = 999
	_check(restored.value.vehicle_presets.ready_at != 999, "存档副本之间不共享可变方案")
	var foreign := VehicleLoadoutPresets.new()
	_check(not foreign.apply(player, 0, 999, 0, player.inventory.revision, player.vehicle.loadout.revision, false).is_ok, "不能借其他集合换装")


## 前置失败逐项比较完整聚合，保证无部分卸装或方案改写。
func _test_rejections() -> void:
	for kind: String in ["incoming_locked", "outgoing_locked", "missing", "inventory_stale", "loadout_stale", "preset_stale", "dead", "capacity", "field_chassis"]:
		var player := _player()
		_check(_capture(player, 0).is_ok, "构造方案：" + kind)
		player.equip_vehicle_item("inventory.spare_engine", 3, player.inventory.revision, player.vehicle.loadout.revision)
		match kind:
			"incoming_locked": player.inventory.find("equipment.engine").locked = true
			"outgoing_locked": player.vehicle.loadout.at(3).locked = true
			"missing": player.inventory.remove_for_transfer("equipment.engine")
			"dead": player.vehicle.health = 0
			"capacity":
				player.inventory.capacity = player.inventory.items().size()
				var missile: VehicleEquipment = catalog.create("starter_missile", {"instance_id": "extra.missile"}).value
				player.vehicle.loadout.equip(missile, 13, player.vehicle.loadout.revision)
			"field_chassis":
				var body: VehicleEquipment = catalog.create("recruit_tank", {"instance_id": "another.chassis"}).value
				var old := player.vehicle.loadout.at(0)
				player.vehicle.loadout.equip(body, 0, player.vehicle.loadout.revision)
				old.equipment_location = -1
				player.inventory.add_from_transfer(old)
		var before := _state(player)
		var result := player.vehicle_presets.apply(player, 0, 100, player.vehicle_presets.revision - int(kind == "preset_stale"),
			player.inventory.revision - int(kind == "inventory_stale"), player.vehicle.loadout.revision - int(kind == "loadout_stale"), kind == "field_chassis")
		_check(not result.is_ok and _state(player) == before, "原子拒绝：" + kind)
		if kind == "field_chassis":
			_check(_apply(player, 0, 100, false).is_ok and player.vehicle.loadout.at(0).instance_id == "equipment.chassis", "城区允许整套切换底盘无需中途卸空")
	# 锁定但未移动的车体不阻止其他槽位互换。
	var player := _player()
	_capture(player, 0)
	player.equip_vehicle_item("inventory.spare_engine", 3, player.inventory.revision, player.vehicle.loadout.revision)
	player.vehicle.loadout.at(0).locked = true
	_check(_apply(player, 0, 100, true).is_ok, "野外同底盘换设备，锁定且未移动的底盘不阻止")
	# 同一台底盘的新旧接合器/发生器等通用槽允许方案整体移动。
	var id := String(catalog.generator_rules.profiles.keys()[0])
	var generator: VehicleEquipment = catalog.create(id, {"instance_id": "slot.moving"}).value
	player.vehicle.loadout.equip(generator, 14, player.vehicle.loadout.revision)
	_capture(player, 2)
	player.vehicle.loadout.unequip(14, player.vehicle.loadout.revision)
	player.vehicle.loadout.equip(generator, 34, player.vehicle.loadout.revision)
	_check(_apply(player, 2, 140).is_ok and player.vehicle.loadout.at(14) == generator \
		and player.vehicle.loadout.at(34) == null, "同一实例跨兼容槽位移动不复制")
	var bad_slots: Array = player.vehicle_presets.at(0).slots
	bad_slots[1].location = 13
	var before := _state(player)
	_check(not VehicleLoadoutExchange.apply(player, bad_slots, player.inventory.revision, player.vehicle.loadout.revision, false).is_ok \
		and _state(player) == before, "合法位置但装备类型不兼容时全量拒绝")


## 校验输入与旧档迁移，命令里的伪造装备和时钟不能覆盖服务端事实。
func _test_persistence_and_commands() -> void:
	var player := _player()
	var command := {"type": "capture_vehicle_preset", "index": 0, "title": "火力方案", "preset_revision": 0,
		"loadout_revision": player.vehicle.loadout.revision, "slots": [{"instance_id": "forged"}], "now": 999999}
	_check(VehiclePresetCommands.execute(player, command, 100).is_ok, "合法保存忽略伪造列表与时钟")
	_check(player.vehicle_presets.at(0).slots.size() == 3, "仅采集真实三件装备")
	command.preset_revision = player.vehicle_presets.revision
	_check(not VehiclePresetCommands.execute(player, command, 100).is_ok, "覆盖必须确认")
	command.confirmed = true
	_check(VehiclePresetCommands.execute(player, command, 100).is_ok, "确认覆盖不消耗装备")
	var raw := player.vehicle_presets.to_dictionary()
	for field: String in ["index", "preset_revision", "loadout_revision"]:
		for invalid: Variant in [-1, 0.5, INF, NAN, "0", true]:
			var bad := command.duplicate(true)
			bad[field] = invalid
			_check(not VehiclePresetCommands.execute(player, bad, 100).is_ok, "拒绝非法命令整数" + field)
	for kind: String in ["duplicate_item", "duplicate_slot", "no_chassis", "bad_time", "too_many", "unknown_slot"]:
		var bad := raw.duplicate(true)
		match kind:
			"duplicate_item": bad.sets[0].slots[1].instance_id = bad.sets[0].slots[0].instance_id
			"duplicate_slot": bad.sets[0].slots[1].location = 0
			"no_chassis": bad.sets[0].slots.pop_front()
			"bad_time": bad.ready_at = NAN
			"too_many": bad.sets.append({})
			"unknown_slot": bad.sets[0].slots[1].location = 999
		_check(not VehicleLoadoutPresets.restore(bad).is_ok, "拒绝非法存档" + kind)
	var old := fixture._state.to_dictionary()
	old.erase("vehicle_presets")
	var restored := PlayerStateRecord.from_dictionary(old)
	_check(restored.is_ok and restored.value.vehicle_presets.at(0).is_empty(), "旧档默认四套空方案")


## 创建拥有真实车炮引擎与备用引擎的隔离玩家。
## 返回完整领域玩家。
func _player() -> Player:
	return mapper.to_domain(fixture._state).value


## 读取用于逐项比对的完整存档载荷。
## [param player] 待比较玩家。
## 返回独立字典。
func _state(player: Player) -> Dictionary:
	return mapper.to_record(player).value.to_dictionary()


## 保存当前真实装配到指定测试方案。
## [param player] 隔离玩家。[param index] 方案序号。
## 返回保存结果。
func _capture(player: Player, index: int) -> DomainResult:
	return player.vehicle_presets.capture(index, "方案%d" % (index + 1), player.vehicle.loadout,
		player.vehicle_presets.revision, player.vehicle.loadout.revision)


## 通过当前版本切换测试方案，时间由测试服务器注入。
## [param player] 隔离玩家。[param index] 方案序号。[param now] 权威时刻。[param field] 是否野外。
## 返回换装结果。
func _apply(player: Player, index: int, now: int, field := false) -> DomainResult:
	return player.vehicle_presets.apply(player, index, now, player.vehicle_presets.revision,
		player.inventory.revision, player.vehicle.loadout.revision, field)


## 汇总完整边界检查，失败不终止其他独立案例。
## [param condition] 预期条件。[param message] 失败原因。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
