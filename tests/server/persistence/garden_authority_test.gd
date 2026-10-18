extends SceneTree

class RejectingRepository extends PlayerStateRepository:
	## 注入一次提交失败，验证冷却与物品同进同退。
	## [param _state] 候选状态。[param _expected_revision] 预期版本。
	## 返回模拟失败。
	func save_player(_state: PlayerStateRecord, _expected_revision: int) -> DomainResult:
		return DomainResult.failure(&"test.write_failed", "模拟提交失败")

var checks := 0
var failures: Array[String] = []
const PEER := 94


## 等待引擎初始化后建立独立服务器和本次测试专用保存文件。
func _initialize() -> void:
	call_deferred("_run")


## 经完整会话检验实际权威位置、失败回滚、关闭重开与旧版本重放。
func _run() -> void:
	_check(bool(RuntimeContentBootstrap.mount_default().get("ok")), "挂载原内容包")
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = "res://content/glory/map_definitions/glory_nft_bl_treeroom1.json"
	config.player_state_store_path = "user://garden-test.json"
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "植物园权威服务器")
	_check(server.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok, "会话")
	var session := server.sessions.session_for_peer(PEER)
	var map := server.map_registry.instance_by_id(session.map_instance_id)
	for point: BotanicalGardenCatalog.Plant in server.garden_service.rules.plants:
		var approach: Vector2 = map.navigation.closest_reachable_position(map.entities[session.entity_id].position, point.position)
		_check(approach.is_finite() and approach.distance_to(point.position) <= server.garden_service.rules.interaction_radius, "点位可接近：" + point.id)
	var plant: BotanicalGardenCatalog.Plant = server.garden_service.rules.plants[0]
	map.entities[session.entity_id].position = map.navigation.closest_reachable_position(map.entities[session.entity_id].position, plant.position)
	var query := server.handle_peer_player_panel_command(PEER, {"type": "query_garden"})
	_check(query.ok and query.value.garden.plants.size() == 15, "实际路由查询15个点")
	var state := server.autosave_service.state_for(session.entity_id)
	var command := {"type": "harvest_garden", "plant_id": plant.id, "inventory_revision": state.inventory_revision}
	var original := server.autosave_service._repository
	server.autosave_service._repository = RejectingRepository.new()
	var before := state.to_dictionary()
	_check(not server.handle_peer_player_panel_command(PEER, command).ok, "提交失败")
	_check(before == server.autosave_service.state_for(session.entity_id).to_dictionary(), "失败不改背包和时钟")
	server.autosave_service._repository = original
	var harvested := server.handle_peer_player_panel_command(PEER, command)
	_check(harvested.ok and harvested.value.garden.plants[0].remaining_seconds > 0, "实际提交成功")
	_check(not server.handle_peer_player_panel_command(PEER, command).ok, "重复请求拒绝")
	server._save_all_persistent_players()
	server.free()
	server = AuthoritativeServer.new()
	_check(server.initialize(config).ok, "重开读取存档")
	_check(server.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok, "重连")
	session = server.sessions.session_for_peer(PEER)
	state = server.autosave_service.state_for(session.entity_id)
	command.inventory_revision = state.inventory_revision
	_check(not server.handle_peer_player_panel_command(PEER, command).ok, "新服务保留未成熟状态")
	query = server.handle_peer_player_panel_command(PEER, {"type": "query_garden"})
	_check(query.ok and query.value.garden.plants[0].remaining_seconds > 0, "重连查询准确时钟")
	server.free()
	print("Garden authority: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 记录权威链路结果并提供故障上下文。
## [param condition] 实际条件。[param message] 期望说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
