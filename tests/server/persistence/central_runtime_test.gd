extends SceneTree

class RejectingRepository extends PlayerStateRepository:
	## 模拟原子存档提交失败，不接受候选。
	## [param _state] 候选状态。[param _expected_revision] 预期版本。
	## 返回写盘错误。
	func save_player(_state: PlayerStateRecord, _expected_revision: int) -> DomainResult:
		return DomainResult.failure(&"test.disk_failure", "测试写盘失败")

const PEER := 99
var checks := 0
var failures := PackedStringArray()
var server: AuthoritativeServer
var config := DedicatedServerConfig.new()
var entity_id := ""


## 延迟启动带真实战斗与独立存档的服务器。
func _initialize() -> void:
	call_deferred("_run")


## 验证中枢消费提交失败不会改变战斗，成功与重启保留真实属性及资源。
func _run() -> void:
	config.network_enabled = false
	config.map_config_path = "res://data/maps/d04_field_zone.json"
	config.default_spawn = Vector2(2412, 2400)
	config.player_state_store_path = "res://.godot/central-runtime-%d.json" % Time.get_ticks_usec()
	if not _boot():
		quit(1)
		return
	var catalog := server.player_panel_service._catalog
	var mapper := server.player_panel_service._mapper
	var player: Player = mapper.to_domain(_state()).value
	player.inventory = Inventory.new(40, 0, 1000000)
	for chip_id: String in CentralRules.CHIP_IDS:
		for grade in [1,3]:
			var id := "central_%s_module_%d" % [chip_id, grade]
			player.inventory.add_reward(catalog.create(id, {"instance_id":id}).value)
	for id: String in ["central_evolution_crystal", "central_flamelight", "central_syancrystal"]:
		player.inventory.add_reward(catalog.create(id, {"instance_id":id}).value)
	_check(server.autosave_service.commit_player_state(entity_id, mapper.to_record(player).value).is_ok, "isolated setup")
	var map := server.map_registry.instance_by_id(_state().map_instance_id)
	var combat := map.combat_module
	var original_attack := int(combat.actors[entity_id].weapons["energy_cannon.primary"].minimum_damage)
	var original_maximum := combat.vehicle_state_for(entity_id).max_health
	var shot := server.handle_peer_use_ability(PEER, UseAbilityIntent.new(map.instance_id, "energy_cannon.primary", Vector2(2500, 2400), 1).to_dictionary())
	_check(shot.ok, "real shot before central activation")
	var ready: Dictionary = combat.actors[entity_id].cooldown_ready_ticks.duplicate(true)
	var energy := combat.vehicle_state_for(entity_id).working_energy
	var health := combat.vehicle_state_for(entity_id).health
	var command := {"type":"change_central", "instance_id":"central_gun_module_1", "confirmed":true, "inventory_revision":_state().inventory_revision}
	var repository := server.autosave_service._repository
	server.autosave_service._repository = RejectingRepository.new()
	var before := _state().to_dictionary()
	var rejected := server.handle_peer_player_panel_command(PEER, command)
	_check(not rejected.ok and _state().to_dictionary() == before, "write failure keeps module and chip")
	_check(combat.actors[entity_id].cooldown_ready_ticks == ready and combat.vehicle_state_for(entity_id).working_energy == energy, "write failure keeps combat")
	server.autosave_service._repository = repository
	_check(server.handle_peer_player_panel_command(PEER, command).ok, "durable chip activation")
	_check(not server.handle_peer_player_panel_command(PEER, command).ok, "replayed consumption rejected")
	_check(combat.actors[entity_id].weapons["energy_cannon.primary"].minimum_damage == original_attack + 20, "chip affects actual cannon")
	_check(combat.vehicle_state_for(entity_id).max_health == original_maximum + 150, "chip affects actual health")
	_check(combat.actors[entity_id].cooldown_ready_ticks == ready and combat.vehicle_state_for(entity_id).working_energy == energy and combat.vehicle_state_for(entity_id).health == health, "activation preserves cooldown and resources")
	var query := server.handle_peer_player_panel_command(PEER, {"type":"query_central"})
	_check(query.ok and query.value.central.grades.gun == 1 and query.value.central_workshop.chips.size() == 6, "real query includes permanent state and workshop separately")
	for chip_id: String in CentralRules.CHIP_IDS:
		if chip_id != "gun": _consume("central_%s_module_1" % chip_id)
		_consume("central_%s_module_3" % chip_id)
	_consume("central_evolution_crystal")
	_check(_state().central.evolved, "durable evolved core")
	_check(combat.actors[entity_id].weapons["energy_cannon.primary"].minimum_damage == original_attack + 350 and combat.vehicle_state_for(entity_id).max_health == original_maximum + 5000, "actual evolved totals")
	_consume("central_flamelight")
	var equipped := server.handle_peer_player_panel_command(PEER, {"type":"equip_vehicle_item", "instance_id":"central_flamelight", "location":40, "inventory_revision":_state().inventory_revision, "loadout_revision":_state().vehicle_loadout_revision})
	_check(equipped.ok, "independent accessory slot")
	_check(combat.actors[entity_id].weapons["energy_cannon.primary"].minimum_damage == original_attack + 390 and combat.vehicle_state_for(entity_id).max_health == original_maximum + 5400, "grown accessory actual stats")
	_check(combat.actors[entity_id].cooldown_ready_ticks == ready and combat.vehicle_state_for(entity_id).working_energy == energy and combat.vehicle_state_for(entity_id).health == health, "all central operations retain firing state")
	_check(not server.handle_peer_use_ability(PEER, UseAbilityIntent.new(map.instance_id, "energy_cannon.primary", Vector2(2500, 2400), 2).to_dictionary()).ok, "no cooldown bypass")
	server._save_all_persistent_players()
	server.free()
	if not _boot():
		quit(1)
		return
	map = server.map_registry.instance_by_id(_state().map_instance_id)
	combat = map.combat_module
	_check(_state().central.evolved and _state().central.core_grade() == 3, "restart retains permanent core")
	_check(combat.actors[entity_id].weapons["energy_cannon.primary"].minimum_damage == original_attack + 390 and combat.vehicle_state_for(entity_id).max_health == original_maximum + 5400, "restart actual combat totals")
	_check(server.handle_peer_player_panel_command(PEER, {"type":"unequip_vehicle_item", "location":40, "inventory_revision":_state().inventory_revision, "loadout_revision":_state().vehicle_loadout_revision}).ok, "unequip accessory")
	_check(combat.actors[entity_id].weapons["energy_cannon.primary"].minimum_damage == original_attack + 350, "unequip keeps character chips only")
	server.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	print("Central runtime: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 消费当前版本的实际背包目标。
## [param id] 物品实例。
func _consume(id: String) -> void:
	_check(server.handle_peer_player_panel_command(PEER, {"type":"change_central", "instance_id":id, "confirmed":true, "inventory_revision":_state().inventory_revision}).ok, "durable consumption " + id)


## 启动仅使用工作区临时文件的真实会话。
## 返回初始化结果。
func _boot() -> bool:
	server = AuthoritativeServer.new()
	var initialized := server.initialize(config)
	_check(initialized.ok, "boot")
	if not initialized.ok: return false
	var joined := server.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000)
	_check(joined.ok, "session")
	if not joined.ok: return false
	entity_id = server.sessions.session_for_peer(PEER).entity_id
	return true


## 读取服务端正式提交状态，拒绝使用未提交候选冒充存档。
## 返回当前隔离角色记录。
func _state() -> PlayerStateRecord:
	return server.autosave_service.state_for(entity_id)


## 收集真实运行期断言。
## [param condition] 预期条件。[param label] 故障描述。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
