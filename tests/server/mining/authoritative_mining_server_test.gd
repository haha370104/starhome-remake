extends SceneTree

const ConfigScript := preload("res://scripts/server/server_config.gd")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const UseAbilityIntentScript := preload("res://scripts/network/contracts/use_ability_intent.gd")

var failures: Array[String] = []
var assertions := 0
var _state_path := "res://tests/.tmp_mining_server_state_%d.json" % Time.get_ticks_usec()


## 执行本测试脚本的全部验证并汇总结果。
func _initialize() -> void:
	_test_authoritative_collection_transaction()
	_remove_state_file()
	if failures.is_empty():
		print("AUTHORITATIVE_MINING_SERVER_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 验证 `test_authoritative_collection_transaction` 对应的业务约束。
func _test_authoritative_collection_transaction() -> void:
	var config := ConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = true
	config.player_state_store_path = _state_path
	config.map_config_path = "res://data/maps/glory_nft_bl_d04.json"
	config.default_spawn = Vector2(1200, 1200)
	var server = ServerScript.new()
	var initialized: Dictionary = server.initialize(config)
	_expect(initialized.ok, "mining server should initialize: %s" % initialized)
	if not initialized.ok:
		return
	var mining_messages: Array[Dictionary] = []
	server.server_message_generated.connect(func(_peer_id: int, message: Dictionary) -> void:
		if message.get("type") == "mining_collected" or message.get("type") == "player_panels":
			mining_messages.append(message)
	)
	var opened: Dictionary = server.open_session(41, {
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"content_version": Protocol.PUBLIC_CONTENT_VERSION,
	}, 1000)
	_expect(opened.ok, "mining actor should open a persisted session")
	if not opened.ok:
		return
	var entity_id := String(opened.value.session.entity_id)
	var source = server.map_instance.mining_module.sources.values()[0]
	var entity = server.map_instance.entities[entity_id]
	entity.position = source.position + Vector2(40, 0)
	entity.target_position = entity.position
	server.map_instance.combat_module.update_actor_position(entity_id, entity.position)
	var intent := UseAbilityIntentScript.new(
		server.map_instance.instance_id,
		"mining.collect",
		source.position,
		1,
	)
	var started: Dictionary = server.handle_peer_use_ability(41, intent.to_dictionary())
	_expect(not started.ok and started.code == &"mining.arm_required", "仅装能量炮不得采矿")
	server.advance_simulation(3.0)
	_expect(source.remaining == 50 and _inventory_quantity(_state(server, entity_id), "iron_ore") == 0,
		"能量炮点击后经过完整周期，矿源与背包都不得变化")
	var initial: Player = server.autosave_service.player_for(entity_id)
	var original_weapon_id := ""
	for equipment: VehicleEquipment in initial.vehicle.loadout.items():
		if equipment.equipment_location == 1:
			original_weapon_id = equipment.instance_id
	var granted: DomainResult = server.player_panel_service.receive_loot(initial, {
		"loot_id": "test.mining.arm", "item_definition_id": "glory_equipment_collector_ac947ee094", "quantity": 1,
	})
	_expect(granted.is_ok, "测试采掘臂入包")
	server.autosave_service.commit_player(entity_id, initial)
	started = server.handle_peer_use_ability(41, intent.to_dictionary())
	_expect(not started.ok and started.code == &"mining.arm_required", "放在背包里的采掘臂不算装备")
	var arm_id := ""
	for stack in _state(server, entity_id).inventory_stacks:
		if stack.item_definition_id == "glory_equipment_collector_ac947ee094":
			arm_id = stack.stack_id
	_expect(_equip(server, entity_id, arm_id).ok, "野外可以把主炮替换为采掘臂")
	_expect(not server.map_instance.combat_module.actors[entity_id].weapons.has("energy_cannon.primary"), "采掘臂不注册能量炮能力")
	var mining_experience: DomainResult = server.player_panel_service._experience_from_event({
		"source": "mined_material", "skill_id": "mining", "quantity": 1,
		"experience_coefficient": 1.0,
	})
	_expect(mining_experience.is_ok and is_equal_approx(float(mining_experience.value.amount), 1.5),
		"one iron grants 1.5 base mining experience")
	mining_experience = server.player_panel_service._experience_from_event({
		"source": "mined_material", "skill_id": "mining", "quantity": 1,
		"experience_coefficient": 5.0,
	})
	_expect(mining_experience.is_ok and is_equal_approx(float(mining_experience.value.amount), 7.5),
		"mining experience scales with mineral coefficient")
	started = server.handle_peer_use_ability(41, intent.to_dictionary())
	_expect(started.ok and StringName(started.value.event_type) == &"mining_started", "server should accept an eligible mine selection")
	_expect(server.snapshot_bundle_for_peer(41).local_snapshot.local_mining.active, "开始后必须同步活动采矿状态")
	server.advance_simulation(2.95)
	var before = _state(server, entity_id)
	_expect(_inventory_quantity(before, "iron_ore") == 0, "inventory must not change before the third second")
	_expect(int(before.achievements.get("counters", {}).get("mine:iron_ore", 0)) == 0, "采矿周期未完成前没有成就进度")
	mining_messages.clear()
	server.advance_simulation(0.05)
	var after = _state(server, entity_id)
	_expect(_inventory_quantity(after, "iron_ore") == 1, "third-second settlement should add one iron ore")
	_expect(int(after.achievements.get("counters", {}).get("mine:iron_ore", 0)) == 1, "真实采矿结算写入同一成就账本")
	_expect(mining_messages.size() == 1 and mining_messages[0].get("type") == "mining_collected",
		"一次采矿周期只下发一次最终面板")
	_expect(source.remaining == 49, "settled collection should reduce the selected source from fifty to forty-nine")
	var snapshot_bundle: Dictionary = server.snapshot_bundle_for_peer(41)
	var world_snapshot: Dictionary = snapshot_bundle.world_snapshot
	var local_snapshot: Dictionary = snapshot_bundle.local_snapshot
	_expect((world_snapshot.combat_world.get("mine_sources", []) as Array).size() == 20, "shared snapshot should publish all twenty authoritative mine sources")
	var client = preload("res://scripts/client/network/client_multiplayer_session.gd").new()
	_expect(client._is_valid_world_snapshot(world_snapshot) and client._is_valid_local_snapshot(local_snapshot), "真实服务端采矿快照必须通过客户端契约校验")
	var invalid_snapshot := local_snapshot.duplicate(true)
	invalid_snapshot.local_mining.target_position = ["bad", 0]
	_expect(not client._is_valid_local_snapshot(invalid_snapshot), "畸形采矿目标不得进入表现层")
	client.free()
	_expect(_equip(server, entity_id, original_weapon_id).ok, "采矿中途切回能量炮")
	_expect(not server.snapshot_bundle_for_peer(41).local_snapshot.local_mining.active, "换装当下立即停止，不等下一个三秒周期")
	_expect(_equip(server, entity_id, arm_id).ok, "短暂切回采掘臂也不能恢复旧采矿动作")
	server.advance_simulation(3.0)
	after = _state(server, entity_id)
	_expect(source.remaining == 49 and _inventory_quantity(after, "iron_ore") == 1, "换炮后到期结算不能扣矿或产矿")
	_expect(int(after.achievements.get("counters", {}).get("mine:iron_ore", 0)) == 1, "中断采矿不增加成就进度")
	intent.input_sequence = 2
	_expect(server.handle_peer_use_ability(41, intent.to_dictionary()).ok, "重新点击才重新开始采矿")
	server.map_instance.mining_module.interrupt(entity_id, &"movement")
	_expect(not server.snapshot_bundle_for_peer(41).local_snapshot.local_mining.active, "移动中断后快照必须关闭采矿动画")
	# 重启同地图服务器并读取真实测试存档，首个周期不能与旧背包矿石编号冲突。
	server.stop_network()
	server.free()
	server = ServerScript.new()
	_expect(server.initialize(config).ok, "持久化矿石后的服务器能够重新初始化")
	opened = server.open_session(41, {
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"content_version": Protocol.PUBLIC_CONTENT_VERSION,
	}, 1000)
	_expect(opened.ok, "重启后重新打开相同玩家存档")
	entity_id = String(opened.value.session.entity_id)
	var restored = _state(server, entity_id)
	_expect(_inventory_quantity(restored, "iron_ore") == 1, "重启确实保留旧矿石而非重置存档")
	_expect(int(restored.achievements.get("counters", {}).get("mine:iron_ore", 0)) == 1, "真实仓储重启保留成就计数")
	var existing_ore_id := ""
	for stack in restored.inventory_stacks:
		if stack.item_definition_id == "iron_ore":
			existing_ore_id = stack.stack_id
	var duplicate_player: Player = server.autosave_service.player_for(entity_id)
	var duplicate: DomainResult = server.player_panel_service.receive_loot(duplicate_player, {
		"loot_id": existing_ore_id, "item_definition_id": "iron_ore", "quantity": 1,
	})
	_expect(not duplicate.is_ok and duplicate.error_code == &"inventory.duplicate_item", "保留重复入账保护，不能靠放行重复编号掩盖问题")
	source = server.map_instance.mining_module.sources.values()[0]
	entity = server.map_instance.entities[entity_id]
	entity.position = source.position + Vector2(40, 0)
	entity.target_position = entity.position
	server.map_instance.combat_module.update_actor_position(entity_id, entity.position)
	intent.map_instance_id = server.map_instance.instance_id
	intent.aim_world_position = source.position
	intent.input_sequence = 1
	_expect(server.handle_peer_use_ability(41, intent.to_dictionary()).ok, "重启后首个采集命令应成功")
	server.advance_simulation(6.0)
	_expect(_inventory_quantity(_state(server, entity_id), "iron_ore") == 3,
		"重启后的两个连续周期应正常叠加到原存档矿石堆")
	_expect(source.remaining == 48, "成功入账与矿量扣减保持一致")
	_expect(int(_state(server, entity_id).achievements.get("counters", {}).get("mine:iron_ore", 0)) == 3, "重启后成就继续累计")
	server.map_instance.mining_module.interrupt(entity_id, &"test")
	var damaged: Player = server.autosave_service.player_for(entity_id)
	for equipment: VehicleEquipment in damaged.vehicle.loadout.items():
		if equipment.equipment_location == 1:
			equipment.durability = 0
	server.autosave_service.commit_player(entity_id, damaged)
	intent.input_sequence = 3
	started = server.handle_peer_use_ability(41, intent.to_dictionary())
	_expect(not started.ok and started.code == &"mining.arm_broken", "损坏的采掘臂不能采矿")
	server.free()


## 经真实权威面板命令替换主装置，不绕过背包与换装事务。
## [param server] 测试权威服务器。
## [param entity_id] 会话对应的玩家实体。
## [param instance_id] 背包内要安装的装备实例。
## 返回服务端换装结果。
func _equip(server: AuthoritativeServer, entity_id: String, instance_id: String) -> Dictionary:
	var state: PlayerStateRecord = _state(server, entity_id)
	return server.handle_peer_player_panel_command(41, {
		"type": "equip_vehicle_item", "instance_id": instance_id, "location": 1,
		"inventory_revision": state.inventory_revision, "loadout_revision": state.vehicle_loadout_revision,
	})


## 将当前权威玩家映射为测试用存档记录。
func _state(server: AuthoritativeServer, entity_id: String) -> PlayerStateRecord:
	var mapped: DomainResult = server.autosave_service.mapper.to_record(
		server.autosave_service.player_for(entity_id)
	)
	return mapped.value


## 执行 `inventory_quantity` 对应的模块操作。
## [param state] 调用方传入的 `state` 参数。
## [param definition_id] 调用方传入的 `definition_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _inventory_quantity(state, definition_id: String) -> int:
	if state == null:
		return 0
	var quantity := 0
	for stack in state.inventory_stacks:
		if stack.item_definition_id == definition_id:
			quantity += stack.quantity
	return quantity


## 执行 `remove_state_file` 对应的模块操作。
func _remove_state_file() -> void:
	var absolute := ProjectSettings.globalize_path(_state_path)
	if FileAccess.file_exists(_state_path):
		DirAccess.remove_absolute(absolute)


## 记录一项测试断言及其失败信息。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
