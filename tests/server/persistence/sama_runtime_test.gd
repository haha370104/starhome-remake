extends SceneTree

class RejectingRepository extends PlayerStateRepository:
	## 模拟原子存档提交失败，不接受候选。
	## [param _state] 候选状态。[param _expected_revision] 预期版本。
	## 返回写盘错误。
	func save_player(_state: PlayerStateRecord, _expected_revision: int) -> DomainResult:
		return DomainResult.failure(&"test.disk_failure", "测试写盘失败")

const PEER := 98
var checks := 0
var failures := PackedStringArray()
var server: AuthoritativeServer
var config := DedicatedServerConfig.new()
var entity_id := ""


## 延迟启动带真实战斗与独立存档的服务器。
func _initialize() -> void:
	call_deferred("_run")


## 检验写盘失败、成长成功、真实攻击属性、射击冷却与重启一致性。
func _run() -> void:
	config.network_enabled = false
	config.map_config_path = "res://data/maps/d04_field_zone.json"
	config.default_spawn = Vector2(2412, 2400)
	config.player_state_store_path = "res://.godot/sama-runtime-%d.json" % Time.get_ticks_usec()
	if not _boot():
		quit(1)
		return
	var catalog := server.player_panel_service._catalog
	var mapper := server.player_panel_service._mapper
	var player: Player = mapper.to_domain(_state()).value
	player.level = 400
	player.inventory = Inventory.new(40, 0, 1000000)
	player.inventory.add_reward(catalog.create("glory_equipment_samajnq_1011d2a44c", {"instance_id": "sama.body"}).value)
	player.inventory.add_reward(catalog.create("sama_capacity_core", {"instance_id":"sama.core", "quantity":6}).value)
	var quote := PlayerSamaActions.quote(player, catalog, "sama.body", "growth", "")
	for cost: Dictionary in quote.value.requirements:
		var remaining := int(cost.quantity)
		while remaining > 0:
			var material: GameItem = catalog.create(cost.definition_id, {"instance_id": "test." + Crypto.new().generate_random_bytes(16).hex_encode()}).value
			material.quantity = mini(material.max_stack, remaining)
			remaining -= material.quantity
			player.inventory.add_reward(material)
	_check(server.autosave_service.commit_player_state(entity_id, mapper.to_record(player).value).is_ok, "isolated setup")
	var map := server.map_registry.instance_by_id(_state().map_instance_id)
	var combat := map.combat_module
	var original_attack := int(combat.actors[entity_id].weapons["energy_cannon.primary"].minimum_damage)
	var original_maximum := combat.vehicle_state_for(entity_id).max_health
	var shot := server.handle_peer_use_ability(PEER, UseAbilityIntent.new(map.instance_id, "energy_cannon.primary", Vector2(2500, 2400), 1).to_dictionary())
	_check(shot.ok, "fire real weapon")
	var ready: Dictionary = combat.actors[entity_id].cooldown_ready_ticks.duplicate(true)
	var energy := combat.vehicle_state_for(entity_id).working_energy
	var health := combat.vehicle_state_for(entity_id).health
	var command := {"type": "change_sama", "instance_id": "sama.body", "mode": "growth", "confirmed": true, "inventory_revision": _state().inventory_revision}
	var repository := server.autosave_service._repository
	server.autosave_service._repository = RejectingRepository.new()
	var before := _state().to_dictionary()
	var rejected := server.handle_peer_player_panel_command(PEER, command)
	_check(not rejected.ok and _state().to_dictionary() == before, "write failure no payment or growth")
	_check(combat.actors[entity_id].cooldown_ready_ticks == ready and combat.vehicle_state_for(entity_id).working_energy == energy, "write failure no combat mutation")
	server.autosave_service._repository = repository
	_check(server.handle_peer_player_panel_command(PEER, command).ok, "durable growth")
	_check(combat.actors[entity_id].cooldown_ready_ticks == ready, "growth preserves firing cooldown")
	_check(not server.handle_peer_player_panel_command(PEER, command).ok, "old command rejected")
	_check(server.handle_peer_player_panel_command(PEER, {"type":"change_sama", "instance_id":"sama.body", "mode":"quality", "confirmed":true, "inventory_revision":_state().inventory_revision}).ok, "durable quality")
	_check(combat.actors[entity_id].weapons["energy_cannon.primary"].minimum_damage == original_attack, "backpack growth inactive")
	var equip := {"type": "equip_vehicle_item", "instance_id": "sama.body", "location": 19, "inventory_revision": _state().inventory_revision, "loadout_revision": _state().vehicle_loadout_revision}
	_check(server.handle_peer_player_panel_command(PEER, equip).ok, "stable special slot resolves")
	_check(combat.actors[entity_id].weapons["energy_cannon.primary"].minimum_damage == original_attack + 7, "actual cannon includes Sama base tracks")
	_check(combat.vehicle_state_for(entity_id).max_health == original_maximum + 65, "actual battle health uses body growth")
	_check(combat.vehicle_state_for(entity_id).working_energy == energy and combat.vehicle_state_for(entity_id).health == health, "special equip preserves absolute resources")
	_check(combat.actors[entity_id].cooldown_ready_ticks == ready, "special equip preserves firing cooldown")
	var repeat_shot := server.handle_peer_use_ability(PEER, UseAbilityIntent.new(map.instance_id, "energy_cannon.primary", Vector2(2500, 2400), 2).to_dictionary())
	_check(not repeat_shot.ok, "cannot bypass cooldown by equipping")
	server._save_all_persistent_players()
	server.free()
	if not _boot():
		quit(1)
		return
	map = server.map_registry.instance_by_id(_state().map_instance_id)
	combat = map.combat_module
	_check(combat.actors[entity_id].weapons["energy_cannon.primary"].minimum_damage == original_attack + 7 and combat.vehicle_state_for(entity_id).max_health == original_maximum + 65, "restart preserves actual effects")
	player = server.player_panel_service._mapper.to_domain(_state()).value
	_check(player.vehicle.loadout.at(19).sama.growth == 1 and player.vehicle.loadout.at(19).sama.quality == 1 and player.vehicle.loadout.at(19).bound, "restart growth quality binding")
	_check(server.handle_peer_player_panel_command(PEER, {"type": "unequip_vehicle_item", "location": 19, "inventory_revision": _state().inventory_revision, "loadout_revision": _state().vehicle_loadout_revision}).ok, "unequip special")
	_check(combat.actors[entity_id].weapons["energy_cannon.primary"].minimum_damage == original_attack and combat.vehicle_state_for(entity_id).max_health == original_maximum, "unequip removes real combat bonuses")
	server.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	print("Sama runtime: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


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
