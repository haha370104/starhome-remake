extends SceneTree

const PEER := 79
var checks := 0
var failures: Array[String] = []


## 在场景树就绪后启动独立权威服务和磁盘存档。
func _initialize() -> void:
	call_deferred("_run")


## 验证实际开火耗弹、运行状态捕获、服务器重启以及临时状态不进入存档。
func _run() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = "res://data/maps/d04_field_zone.json"
	config.player_state_store_path = "res://.godot/generator-persistence-%d.json" % Time.get_ticks_usec()
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "权威服务器")
	_check(server.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok, "会话")
	var session := server.sessions.session_for_peer(PEER)
	var map := server.map_registry.instance_by_id(session.map_instance_id)
	var current := server.autosave_service.state_for(session.entity_id)
	var catalog := ItemCatalog.new()
	_check(catalog.initialize().is_ok, "目录")
	var player: Player = server.player_panel_service.restore_player(current).value
	var item: VehicleEquipment = catalog.create("glory_equipment_gaoregun_217b753365", {"instance_id": "persist.generator"}).value
	_check(player.vehicle.loadout.equip(item, 14, player.vehicle.loadout.revision).is_ok, "装配发生器")
	current = PlayerStateMapper.new(catalog).to_record(player).value
	_check(server.autosave_service.commit_player_state(session.entity_id, current).is_ok, "提交测试装备")
	var loadout := server._build_entity_combat_loadout(map, current)
	var profile: GeneratorRules.Profile = loadout.value.assembly.equipment_condition.generators()[0].generator_profile
	profile.chance = 1
	_check(map.refresh_achievement_loadout(session.entity_id, loadout.value).is_ok, "运行期装配")
	var module := map.combat_module
	module.monsters.clear()
	var origin: Vector2 = module.actors[session.entity_id].position
	var aim := origin + Vector2(100, 0)
	_check(module.register_monster({"monster_id": "persist.monster", "map_instance_id": map.instance_id,
		"position": aim, "max_health": 10000, "respawn_seconds": 30,
		"projectile_hitbox": {"offset": [0, -16], "radius": 30}}).is_ok, "实际命中目标")
	var intent := UseAbilityIntent.new(map.instance_id, "energy_cannon.primary", aim, 1).to_dictionary()
	_check(module.handle_weapon_attack(session.entity_id, intent).is_ok, "开火")
	module.advance_ticks(20, false)
	var condition: EquipmentConditionLoadout = module.actors[session.entity_id].equipment_condition
	_check(condition.generators()[0].magazine.remaining == 1199, "命中实际消耗1发")
	var captured: PlayerStateRecord = server._capture_persistent_player_state(server.autosave_service.state_for(session.entity_id)).value
	var saved_count := -1
	for slot: EquipmentSlotRecord in captured.equipment_slots:
		if slot.item_instance_id == item.instance_id: saved_count = slot.magazine.remaining
	_check(saved_count == 1199, "运行期弹仓进入存档捕获")
	server._save_all_persistent_players()
	server.free()
	var restarted := AuthoritativeServer.new()
	_check(restarted.initialize(config).ok, "重启")
	_check(restarted.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok, "重连")
	var restored_session := restarted.sessions.session_for_peer(PEER)
	var restored_map := restarted.map_registry.instance_by_id(restored_session.map_instance_id)
	var restored_condition: EquipmentConditionLoadout = restored_map.combat_module.actors[restored_session.entity_id].equipment_condition
	_check(restored_condition.generators().size() == 1 and restored_condition.generators()[0].magazine.remaining == 1199, "重启不补弹")
	for monster: MonsterLifecycle in restored_map.combat_module.monsters.values():
		_check(monster.generator_afflictions.labels().is_empty(), "重启无临时状态")
	restarted.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	print("Generator persistence: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 记录重启与保存断言。
## [param condition] 当前预期。
## [param label] 失败描述。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
