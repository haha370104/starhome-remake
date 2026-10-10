extends SceneTree

const PEER := 91
var failures: Array[String] = []
var seen_ids: Array[String] = []

class RejectingRepository extends FilePlayerStateRepository:
	var reject_transfer := false
	func save_player(state: PlayerStateRecord, expected_revision: int) -> DomainResult:
		return DomainResult.failure(&"test.disk_failed", "injected failure") if reject_transfer else super.save_player(state, expected_revision)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for map_path: String in ["yian_harbor_hall_floor_1", "glory_nft_bl_d04"]:
		var config := DedicatedServerConfig.new()
		config.network_enabled = false
		config.map_config_path = "res://data/maps/%s.json" % map_path
		config.player_state_store_path = "res://.godot/loot-pickup-%d.json" % Time.get_ticks_usec()
		for generation in 2:
			var server := AuthoritativeServer.new()
			assert(server.initialize(config).ok)
			assert(server.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok)
			var session := server.sessions.session_for_peer(PEER)
			var map := server.map_registry.instance_by_id(session.map_instance_id)
			var module := map.combat_module
			var player := server.autosave_service.player_for(session.entity_id)
			var catalog := server.player_panel_service.catalog
			var identity := "dropped.engine.%d" % generation
			var engine: Equipment = catalog.create("beginner_engine", {"instance_id": identity}).value
			engine.durability -= 7
			assert(player.inventory.add_reward(engine).is_ok)
			var position: Vector2 = map.entities[session.entity_id].position
			var command := {"type": "drop_inventory_item", "instance_id": identity, "inventory_revision": player.inventory.revision,
				"map_instance_id": session.map_instance_id, "position": [position.x, position.y]}
			for invalid: Array in [[INF, position.y], [true, position.y], [position.x + 500, position.y]]:
				command.position = invalid
				_check(not server.handle_peer_player_panel_command(PEER, command).ok and module.ground_loot.is_empty()
					and player.inventory.find(identity) != null, "非法或远处落点拒绝，物品不变")
			command.position = [position.x, position.y]
			engine.bound = true
			_check(not server.handle_peer_player_panel_command(PEER, command).ok, "绑定物品不可扔出")
			engine.bound = false
			engine.locked = true
			_check(not server.handle_peer_player_panel_command(PEER, command).ok, "锁定物品不可扔出")
			engine.locked = false
			var dropped := server.handle_peer_player_panel_command(PEER, command)
			_check(dropped.ok, "城内和野外都可放下物品：%s" % dropped)
			if not dropped.ok:
				server.free()
				break
			_check(player.inventory.find(identity) == null and module.ground_loot.size() == 1, "背包移除并生成地面物品")
			_check(not server.handle_peer_player_panel_command(PEER, command).ok, "重复丢弃拒绝")
			var loot_id: String = module.ground_loot.keys()[0]
			_check(not seen_ids.has(loot_id), "跨地图及重启不复用掉落编号")
			seen_ids.append(loot_id)
			_check(map.world_snapshot(0, 0).combat_world.ground_loot.size() == 1, "地面物品进入共享快照")
			player.inventory.capacity = player.inventory.items().size()
			_check(not server.handle_peer_loot_pickup(PEER, {"loot_id": loot_id}).ok and module.ground_loot.has(loot_id), "满包拾取失败不吞物品")
			player.inventory.capacity = InventoryLayout.ITEM_LIMIT
			_check(server.handle_peer_loot_pickup(PEER, {"loot_id": loot_id}).ok, "拾回原物品")
			_check(player.inventory.find(identity).durability == engine.durability and module.dropped_items.is_empty(), "身份耐久保留且地面引用移除")
			_check(not server.handle_peer_loot_pickup(PEER, {"loot_id": loot_id}).ok, "重复拾取拒绝")
			if not module.monsters.is_empty():
				var monster: MonsterLifecycle = module.monsters.values()[0]
				monster.position = position
				monster.drop_table.configure([{"item_definition_id": "low_grade_gel", "chance": 1.0, "minimum_quantity": 2, "maximum_quantity": 2}])
				for index in 60:
					var loot: Dictionary = module._spawn_monster_loot(monster, session.entity_id)[0]
					_check(server.handle_peer_loot_pickup(PEER, {"loot_id": loot.loot_id}).ok, "怪物连续掉落仍可拾取")
				_check(player.inventory.count_definition("low_grade_gel") == (generation + 1) * 120, "连续拾取数量守恒并跨重启保存")
			if generation == 1:
				_check(player.inventory.find("dropped.engine.0").durability == engine.durability, "拾回的物品耐久跨重启保存")
			server._save_all_persistent_players()
			server.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	_test_ground_persistence()
	for failure: String in failures: push_error(failure)
	print("LOOT_PICKUP_AUTHORITY failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _test_ground_persistence() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.player_state_store_path = "res://.godot/ground-persistence-%d.json" % Time.get_ticks_usec()
	var repository := RejectingRepository.new(config.player_state_store_path)
	var server := AuthoritativeServer.new()
	assert(server.initialize(config, [], repository).ok)
	assert(repository.enable_background_writes().is_ok)
	var handshake := {"protocol_version": config.protocol_version, "content_version": config.content_version}
	assert(server.open_session(PEER, handshake, 1000).ok)
	var session := server.sessions.session_for_peer(PEER)
	var player := server.autosave_service.player_for(session.entity_id)
	var map := server.map_registry.instance_by_id(session.map_instance_id)
	var map_id := String(map.definition.map_id)
	var position: Vector2 = map.entities[session.entity_id].position
	var deadline := repository.ground_cleanup_at + PlayerStateRepository.GROUND_CLEAR_INTERVAL
	repository.ground_cleanup_at = deadline
	server._ground_cleanup_at = deadline
	for index in 3:
		var item: Equipment = server.player_panel_service.catalog.create("beginner_engine", {"instance_id": "arranged.%d" % index}).value
		item.durability -= index + 1
		player.inventory.add_reward(item)
		var command := {"type": "drop_inventory_item", "instance_id": item.instance_id,
			"inventory_revision": player.inventory.revision, "map_instance_id": map.instance_id,
			"position": [position.x + index * 0.5, position.y]}
		if index == 0:
			repository.reject_transfer = true
			_check(not server.handle_peer_player_panel_command(PEER, command).ok and repository.ground_items.is_empty()
				and player.inventory.find(item.instance_id) == item and map.combat_module.ground_loot.is_empty(), "保存拒绝时背包、地面和仓储都不变")
			repository.reject_transfer = false
		_check(server.handle_peer_player_panel_command(PEER, command).ok, "自由摆放进入同一存档事务")
	var layout: Dictionary = repository.ground_items[map_id].duplicate(true)
	var failed_pickup_id: String = layout.keys()[0]
	var failed_pickup_item: GameItem = map.combat_module.dropped_items[failed_pickup_id]
	repository.reject_transfer = true
	_check(not server.handle_peer_loot_pickup(PEER, {"loot_id": failed_pickup_id}).ok
		and player.inventory.find(failed_pickup_item.instance_id) == null
		and repository.ground_items[map_id] == layout and map.combat_module.dropped_items[failed_pickup_id] == failed_pickup_item,
		"拾取保存失败时，背包、地面和存档索引均不变")
	repository.reject_transfer = false
	var policy := SmartAssistantPolicy.new()
	_check(policy.nearest(map.combat_module.ground_loot.values(), position, 125, false).is_empty(), "智脑不自动捡走玩家摆放物品")
	server._clear_due_ground_items(deadline - 1)
	_check(map.combat_module.ground_loot.size() == 3, "现实清理时间前保留摆放")
	var exit_command := {"type": "prepare_exit", "request_id": "0123456789abcdef0123456789abcdef"}
	_check(server.handle_peer_player_panel_command(PEER, exit_command).ok, "正常退出持久化地面布局")
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.player_state_store_path))
	_check(disk.ground_items[map_id] == JSON.parse_string(JSON.stringify(layout)), "完整属性与精确世界坐标写入磁盘")
	server.free()
	config.map_config_path = "res://data/maps/glory_nft_bl_d04.json"
	server = AuthoritativeServer.new()
	assert(server.initialize(config).ok)
	_check(server.map_registry.instance_by_map_id(map_id) == null and server.player_state_repository.ground_items[map_id] == JSON.parse_string(JSON.stringify(layout)),
		"未加载地图的摆放仍保留，不为恢复物品加载全世界")
	assert(server.open_session(PEER, handshake, 1000).ok)
	session = server.sessions.session_for_peer(PEER)
	player = server.autosave_service.player_for(session.entity_id)
	map = server.map_registry.instance_by_id(session.map_instance_id)
	_check(map.combat_module.ground_loot.size() == 3 and player.inventory.find("arranged.0") == null, "重启回图恢复摆放且背包没有副本")
	for loot_id: String in layout:
		var dropped: GameItem = map.combat_module.dropped_items[loot_id]
		_check(InventoryStackRecord.from_item(dropped, 0).value.to_dictionary() == layout[loot_id].item
			and map.combat_module.ground_loot[loot_id].position == layout[loot_id].position, "重启不吸附、不重建装备属性")
	var picked_id: String = layout.keys()[0]
	_check(server.handle_peer_loot_pickup(PEER, {"loot_id": picked_id}).ok, "恢复的摆放可拾取")
	server._save_all_persistent_players()
	server.free()
	server = AuthoritativeServer.new()
	assert(server.initialize(config).ok)
	_check(not server.player_state_repository.ground_items[map_id].has(picked_id), "拾取后重启不复活地面副本")
	assert(server.open_session(PEER, handshake, 1000).ok)
	session = server.sessions.session_for_peer(PEER)
	map = server.map_registry.instance_by_id(session.map_instance_id)
	var field := server.map_registry.instance_by_map_id("glory_nft_bl_d04")
	var monster: MonsterLifecycle = field.combat_module.monsters.values()[0]
	monster.drop_table.configure([{"item_definition_id": "low_grade_gel", "chance": 1.0, "minimum_quantity": 1, "maximum_quantity": 1}])
	field.combat_module._spawn_monster_loot(monster, session.entity_id)
	server.map_registry.suspend_empty_instances(0)
	server._clear_due_ground_items(deadline)
	_check(map.combat_module.ground_loot.is_empty() and field.combat_module.ground_loot.is_empty()
		and field.combat_module._loot_spatial_grid.query_circle(monster.position, 125).is_empty()
		and server.player_state_repository.ground_items.is_empty(), "整点统一清理活跃图、休眠图、怪物掉落和空间索引")
	_check(server._ground_cleanup_at == deadline + PlayerStateRepository.GROUND_CLEAR_INTERVAL, "清理后按现实一天推进，不按运行时长重置")
	server._save_all_persistent_players()
	server.free()
	disk = JSON.parse_string(FileAccess.get_file_as_string(config.player_state_store_path))
	layout.erase(picked_id)
	disk.ground_items = {map_id: layout}
	disk.ground_cleanup_at = PlayerStateRepository.GROUND_CLEAR_INTERVAL
	_check(AtomicJsonFile.write_document(ProjectSettings.globalize_path(config.player_state_store_path), disk).is_ok, "构造关服期间跨清理时点")
	server = AuthoritativeServer.new()
	assert(server.initialize(config).ok)
	_check(server.player_state_repository.ground_items.is_empty(), "离线跨过清理时点，启动先清理")
	server.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
