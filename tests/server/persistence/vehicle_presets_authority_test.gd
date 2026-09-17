extends SceneTree

class RejectingRepository extends PlayerStateRepository:
	## 模拟真实提交失败，候选不能写回玩家运行状态。
	## [param _state] 待拒绝候选。[param _expected_revision] 预期版本。
	## 返回仓储故障。
	func save_player(_state: PlayerStateRecord, _expected_revision: int) -> DomainResult:
		return DomainResult.failure(&"test.disk_failure", "模拟写盘失败")

const PEER := 96
var checks := 0
var failures: Array[String] = []
var server: AuthoritativeServer
var config := DedicatedServerConfig.new()
var entity_id := ""


## 延迟运行带真实会话、战斗与隔离仓储的换装测试。
func _initialize() -> void:
	call_deferred("_run")


## 检验原子写盘、实时武器冷却、资源守恒、伪造地图与重启冷却。
func _run() -> void:
	config.network_enabled = false
	config.map_config_path = "res://data/maps/d04_field_zone.json"
	config.default_spawn = Vector2(2412, 2400)
	config.player_state_store_path = "res://.godot/presets-authority-%d.json" % Time.get_ticks_usec()
	if not _boot():
		quit(1)
		return
	var catalog := server.player_panel_service._catalog
	var mapper := server.player_panel_service._mapper
	var player: Player = mapper.to_domain(_state()).value
	player.inventory.add_reward(catalog.create("beginner_engine", {"instance_id": "preset.alternate"}).value)
	_check(server.autosave_service.commit_player_state(entity_id, mapper.to_record(player).value).is_ok, "写入隔离备用装备")
	var map := server.map_registry.instance_by_id(_state().map_instance_id)
	var combat := map.combat_module
	_check(map.is_vehicle_combat_active() and combat.actors.has(entity_id), "实际野外战斗对象")
	var original_engine := ""
	for slot: EquipmentSlotRecord in _state().equipment_slots:
		if slot.slot_location == 3: original_engine = slot.item_instance_id
	var shot := server.handle_peer_use_ability(PEER, UseAbilityIntent.new(map.instance_id,
		"energy_cannon.primary", Vector2(2500, 2400), 1).to_dictionary())
	_check(shot.ok, "真实开火进入冷却")
	var ready: Dictionary = combat.actors[entity_id].cooldown_ready_ticks.duplicate(true)
	_check(not ready.is_empty(), "记录真实开火冷却")
	var capture := _command("capture_vehicle_preset", 0)
	capture.title = "原装引擎"
	_check(server.handle_peer_player_panel_command(PEER, capture).ok, "保存第一套实际装配")
	_check(combat.actors[entity_id].cooldown_ready_ticks == ready, "仅保存方案不会重置开火时序")
	var equipped := server.handle_peer_player_panel_command(PEER, {"type": "equip_vehicle_item", "instance_id": "preset.alternate", "location": 3,
		"inventory_revision": _state().inventory_revision, "loadout_revision": _state().vehicle_loadout_revision})
	_check(equipped.ok, "装配第二套测试设备")
	capture = _command("capture_vehicle_preset", 1)
	capture.title = "备用引擎"
	_check(server.handle_peer_player_panel_command(PEER, capture).ok, "保存第二套")
	shot = server.handle_peer_use_ability(PEER, UseAbilityIntent.new(map.instance_id,
		"energy_cannon.primary", Vector2(2500, 2400), 2).to_dictionary())
	_check(shot.ok, "重建测试用冷却")
	ready = combat.actors[entity_id].cooldown_ready_ticks.duplicate(true)
	var working := combat.vehicle_state_for(entity_id).working_energy
	var real_repository := server.autosave_service._repository
	server.autosave_service._repository = RejectingRepository.new()
	var before := _state().to_dictionary()
	var apply := _command("apply_vehicle_preset", 0)
	var result := server.handle_peer_player_panel_command(PEER, apply)
	_check(not result.ok and _state().to_dictionary() == before, "写盘失败不提交换装或冷却")
	_check(combat.actors[entity_id].cooldown_ready_ticks == ready \
		and combat.vehicle_state_for(entity_id).working_energy == working, "失败不影响实时战斗")
	server.autosave_service._repository = real_repository
	result = server.handle_peer_player_panel_command(PEER, apply)
	_check(result.ok and _engine_id() == original_engine, "成功一次提交完整装配")
	_check(combat.actors[entity_id].cooldown_ready_ticks == ready, "应用方案保留真实武器冷却")
	_check(combat.vehicle_state_for(entity_id).working_energy == working \
		and _state().working_energy == working, "已消耗能源同步到战斗与持久化")
	_check(_state().vehicle_presets.ready_at >= int(Time.get_unix_time_from_system()) + 28, "只采用服务端当前时刻开始30秒冷却")
	_check(not server.handle_peer_player_panel_command(PEER, apply).ok, "重发旧意图拒绝")
	var cooldown_request := _command("apply_vehicle_preset", 1)
	cooldown_request.now = 9999999999
	_check(not server.handle_peer_player_panel_command(PEER, cooldown_request).ok, "伪造客户端时间不能绕过冷却")
	_check(not server.handle_peer_player_panel_command(999, cooldown_request).ok, "未知会话无权换装")
	var deadline := _state().vehicle_presets.ready_at
	server._save_all_persistent_players()
	server.free()
	if not _boot():
		quit(1)
		return
	_check(_state().vehicle_presets.ready_at == deadline and _engine_id() == original_engine, "重启保留方案装备和冷却")
	_check(not server.handle_peer_player_panel_command(PEER, _command("apply_vehicle_preset", 1)).ok, "重连后仍需等待冷却")
	# 通过测试夹具准备不同底盘方案；正式客户端不能改写它。
	player = mapper.to_domain(_state()).value
	var previous := player.vehicle.loadout.at(0)
	var different: VehicleEquipment = catalog.create(previous.definition_id, {"instance_id": "different.chassis"}).value
	player.vehicle.loadout.equip(different, 0, player.vehicle.loadout.revision)
	player.vehicle_presets.capture(2, "不同底盘", player.vehicle.loadout, player.vehicle_presets.revision, player.vehicle.loadout.revision)
	player.vehicle.loadout.equip(previous, 0, player.vehicle.loadout.revision)
	different.equipment_location = -1
	player.inventory.add_reward(different)
	player.vehicle_presets.ready_at = 0
	server.autosave_service.commit_player_state(entity_id, mapper.to_record(player).value)
	var forged := _command("apply_vehicle_preset", 2)
	forged["_authoritative_vehicle_combat_active"] = false
	result = server.handle_peer_player_panel_command(PEER, forged)
	_check(not result.ok and result.code == &"equipment.chassis_change_forbidden_in_field", "权威地图覆盖客户端伪造字段")
	server.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	for failure in failures: push_error(failure)
	print("VEHICLE_PRESETS_AUTHORITY_%s (%d checks)" % ["OK" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


## 启动隔离服务器并以相同身份连接，不使用玩家日常存档。
## 返回启动与会话结果。
func _boot() -> bool:
	server = AuthoritativeServer.new()
	var initialized := server.initialize(config)
	_check(initialized.ok, "启动服务器")
	if not initialized.ok: return false
	var joined := server.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000)
	_check(joined.ok, "绑定实际会话")
	if not joined.ok: return false
	entity_id = server.sessions.session_for_peer(PEER).entity_id
	return true


## 读取当前正式提交状态以构造版本化意图。
## 返回隔离角色状态。
func _state() -> PlayerStateRecord:
	return server.autosave_service.state_for(entity_id)


## 查询实际持久化引擎身份。
## 返回引擎实例标识。
func _engine_id() -> String:
	for slot: EquipmentSlotRecord in _state().equipment_slots:
		if slot.owner_kind == "vehicle" and slot.slot_location == 3: return slot.item_instance_id
	return ""


## 创建只包含用户意图与当前库存、方案、装配版本的命令。
## [param kind] 操作类型。[param index] 方案位置。
## 返回可通过正式会话提交的字典。
func _command(kind: String, index: int) -> Dictionary:
	return {"type": kind, "index": index, "preset_revision": _state().vehicle_presets.revision,
		"inventory_revision": _state().inventory_revision, "loadout_revision": _state().vehicle_loadout_revision}


## 累积可读失败信息。
## [param condition] 预期条件。[param message] 失败原因。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
