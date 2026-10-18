extends SceneTree

const PEER := 91
var checks := 0
var failures: Array[String] = []


## 等待地图挂载后运行真实服务端丢弃与拾取链路。
func _initialize() -> void:
	call_deferred("_run")


## 验证室内外共用地面实例、重复操作拒绝、重启和原有掉落互不干扰。
func _run() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.player_state_store_path = "user://ground-authority.json"
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "server")
	_check(server.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok, "session")
	var session := server.sessions.session_for_peer(PEER)
	var id := session.entity_id
	var state := server.autosave_service.state_for(id)
	var catalog := server.player_panel_service.item_catalog()
	var player: Player = server.player_panel_service.restore_player(state).value
	var created := catalog.create("recruit_energy_cannon", {"instance_id": "ground.gun", "durability": 333,
		"processing": {"increments": {"base_attack": 2, "range": 10}}})
	_check(created.is_ok and player.inventory.add_reward(created.value).is_ok, "test processed weapon")
	var candidate := PlayerStateMapper.new(catalog).to_record(player)
	_check(server.autosave_service.commit_player_state(id, candidate.value).is_ok, "fixture commit")
	var command := {"type": "drop_inventory_item", "instance_id": "ground.gun", "inventory_revision": player.inventory.revision}
	var far := command.duplicate()
	far.position = [100000, 100000]
	_check(not server.handle_peer_player_panel_command(PEER, far).ok, "blocked or far drop rejected")
	var dropped := server.handle_peer_player_panel_command(PEER, command)
	_check(dropped.ok, "context command drops weapon")
	if not dropped.ok:
		server.free()
		_finish()
		return
	var loot_id := String(dropped.value.item_dropped.loot_id)
	_check(not server.handle_peer_player_panel_command(PEER, command).ok, "replayed drop rejected")
	var snapshot := server.snapshot_for_peer(PEER)
	_check(snapshot.combat.ground_loot.any(func(entry: Dictionary) -> bool: return entry.loot_id == loot_id), "indoor snapshot includes dropped item")
	server._save_all_persistent_players()
	server.free()
	server = AuthoritativeServer.new()
	_check(server.initialize(config).ok, "server restart")
	_check(server.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok, "session restart")
	snapshot = server.snapshot_for_peer(PEER)
	_check(snapshot.combat.ground_loot.any(func(entry: Dictionary) -> bool: return entry.loot_id == loot_id), "ground remains visible after restart")
	var received := server.handle_peer_loot_pickup(PEER, {"loot_id": loot_id})
	_check(received.ok, "normal pickup command receives full equipment")
	_check(not server.handle_peer_loot_pickup(PEER, {"loot_id": loot_id}).ok, "replayed pickup rejected")
	player = server.player_panel_service.restore_player(server.autosave_service.state_for(id)).value
	var gun := player.inventory.find("ground.gun") as VehicleWeapon
	_check(gun != null and gun.durability == 333 and gun.base_attack == 9 and gun.attack_range == 260, "server round trip keeps processing and durability")
	_check(server.snapshot_for_peer(PEER).combat.ground_loot.is_empty(), "successful pickup clears ground snapshot")
	server.free()
	_finish()


## 输出累计结果。
func _finish() -> void:
	print("GROUND_ITEM_AUTHORITY checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 收集端到端断言。
## [param condition] 预期为真。[param message] 失败原因。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
