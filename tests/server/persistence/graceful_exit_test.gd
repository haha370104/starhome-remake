extends SceneTree

class RejectingRepository extends PlayerStateRepository:
	## 注入可恢复的实际存档拒绝，不接触用户文件。
	## [param _state] 不会写入的候选。[param _expected_revision] 预期版本。
	## 返回模拟磁盘故障。
	func save_player(_state: PlayerStateRecord, _expected_revision: int) -> DomainResult:
		return DomainResult.failure(&"test.write_failed", "模拟保存失败")

const PEER := 97
const REQUEST_ID := "0123456789abcdef0123456789abcdef"
var checks := 0
var failures: Array[String] = []
var messages: Array[Dictionary] = []


## 延迟验证完整生产与战斗退出事务。
func _initialize() -> void:
	call_deferred("_run")


## 在两种真实地图中检验保存失败、回执重试、实体收尾及重启。
func _run() -> void:
	_test_exit(false)
	_test_exit(true)
	for failure in failures: push_error(failure)
	print("GRACEFUL_EXIT_%s (%d checks)" % ["OK" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


## 构造生产或战斗进行中的正式角色，正常退出必须只保存一次完整状态。
## [param production] 是否检验真实生产时钟。
func _test_exit(production: bool) -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = "res://content/glory/map_definitions/glory_nft_bl_factory1.json" if production else "res://data/maps/d04_field_zone.json"
	config.default_spawn = Vector2(1104, 420) if production else Vector2(2412, 2400)
	config.player_state_store_path = "res://.godot/exit-%d-%s.json" % [Time.get_ticks_usec(), str(production)]
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "初始化真实服务器")
	var handshake := {"protocol_version": config.protocol_version, "content_version": config.content_version}
	_check(server.open_session(PEER, handshake, 1000).ok, "连接实际角色")
	server.server_message_generated.connect(func(_peer: int, message: Dictionary) -> void: messages.append(message.duplicate(true)))
	var session := server.sessions.session_for_peer(PEER)
	var identity := session.entity_id
	var token := session.reconnect_token
	var map := server.map_registry.instance_by_id(session.map_instance_id)
	var raw_before := server.autosave_service.state_for(identity)
	var expected_remaining := 0
	if production:
		var mapper: PlayerStateMapper = server.manufacturing_service._mapper
		var catalog: ItemCatalog = server.manufacturing_service._item_catalog
		var player: Player = mapper.to_domain(raw_before).value
		player.skills = SkillBook.new({"refining": 100})
		player.inventory = Inventory.new()
		var recipe: ManufacturingRecipe
		for value: ManufacturingRecipe in server.manufacturing_service._recipe_book.recipes_for_station("refining"):
			if catalog.display_name(value.product_definition_id) == "铁": recipe = value
		_check(recipe != null, "真实铁矿配方")
		player.inventory.add_reward(catalog.create(recipe.materials[0].definition_id, {"instance_id": "exit.ore", "quantity": 60}).value)
		server.autosave_service.commit_player_state(identity, mapper.to_record(player).value)
		var started := server.handle_peer_player_panel_command(PEER, {"type": "start_production", "station_id": "refining",
			"recipe_id": recipe.recipe_id, "cycles": 3, "speed": 1,
			"inventory_revision": player.inventory.revision, "production_revision": 0})
		_check(started.ok, "实际开启生产")
		server.advance_simulation(0.6, 1001)
		expected_remaining = 1400
	else:
		var combat := map.vehicle_combat_state_for(identity)
		combat.health = 35
		combat.reserve_energy = 1777
		combat.working_energy = 17.5
	var current := server.autosave_service.state_for(identity)
	var before := current.to_dictionary()
	for invalid: Variant in [null, 123, "", "0123", "g".repeat(32)]:
		_check(not server.handle_peer_player_panel_command(PEER, {"type": "prepare_exit", "request_id": invalid}).ok, "拒绝非法请求身份")
	var command := {"type": "prepare_exit", "request_id": REQUEST_ID, "currency": 999999999, "character_id": "other"}
	var real_repository := server.autosave_service._repository
	server.autosave_service._repository = RejectingRepository.new()
	server.dispatch_transport_command(PEER, AuthoritativeServer.TRANSPORT_PLAYER_PANEL_COMMAND, command)
	var rejected: Dictionary = messages[-1]
	_check(rejected.type == "command_rejected" and rejected.result.value.request_id == REQUEST_ID, "失败回包带匹配的退出身份")
	_check(server.autosave_service.state_for(identity).to_dictionary() == before, "保存失败不改正式资源或生产状态")
	_check(server.sessions.session_for_peer(PEER) == session and map.entities.has(identity), "失败不能清理会话与实体")
	server.autosave_service._repository = real_repository
	var saves := server.autosave_service.save_count
	server.dispatch_transport_command(PEER, AuthoritativeServer.TRANSPORT_PLAYER_PANEL_COMMAND, command)
	var receipt: Dictionary = messages[-1]
	_check(receipt.type == "player_panels" and receipt.result.ok and receipt.result.value.exit_receipt.request_id == REQUEST_ID, "仅成功写盘后回执确认")
	_check(server.autosave_service.save_count == saves + 1, "一次退出只提交一次")
	_check(server.sessions.session_for_peer(PEER) == null and not map.entities.has(identity) \
		and not map.combat_module.actors.has(identity) and server.autosave_service.state_for(identity) == null, "回执之前结束角色全部运行所有权")
	var saved: PlayerStateRecord = real_repository.load_player(identity).value
	_check(saved.currency == current.currency and saved.inventory_stacks.size() == current.inventory_stacks.size(), "客户端不能伪造退出存档内容")
	if production:
		_check(saved.production.order.paused and saved.production.order.remaining_milliseconds == expected_remaining \
			and saved.production.order.completed == 0, "保存真实剩余等待并暂停未完成生产")
		_check(not server._production_runtime._clocks.has(identity), "退出清除生产时钟")
	else:
		_check(saved.vehicle_health == 35 and saved.reserve_energy == 1777 and saved.working_energy == 17.5, "保存最新战斗生命与两种能量")
	server.advance_simulation(3, 1002)
	server._save_all_persistent_players()
	_check(real_repository.load_player(identity).value.to_dictionary() == saved.to_dictionary(), "退出后不会暗中战斗或生产改写存档")
	var repeated := server.handle_peer_player_panel_command(PEER, command)
	_check(repeated.ok and repeated.value == receipt.result.value and server.autosave_service.save_count == saves + 1, "丢包重试获得原回执不重复写盘")
	_check(not server.handle_peer_player_panel_command(999, command).ok, "其他连接不能获取此回执")
	var reconnect := handshake.duplicate(true)
	reconnect.reconnect_token = token
	_check(not server.open_session(PEER, reconnect, 1003).ok, "正常退出结束旧重连令牌")
	_check(server.open_session(PEER, handshake, 1004).ok, "同一连接编号可开始新会话")
	var new_id := server.sessions.session_for_peer(PEER).entity_id
	_check(server.handle_peer_player_panel_command(PEER, command).ok \
		and real_repository.load_player(new_id).is_ok and server.autosave_service.save_count == saves + 2, "新会话必须保存新角色而非复用旧回执")
	server.free()
	var restarted := AuthoritativeServer.new()
	_check(restarted.initialize(config).ok and restarted.open_session(PEER, handshake, 1000).ok, "退出后的存档可以重新进入")
	var restored := restarted.autosave_service.state_for(identity)
	_check(restored != null and restored.currency == saved.currency and restored.vehicle_health == saved.vehicle_health, "重启还原最后确认的角色内容")
	if production:
		_check(restored.production.order.paused and restored.production.order.remaining_milliseconds == expected_remaining, "重启不会补跑退出期间生产")
	restarted.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))


## 汇总两套正式退出流程的验证结果。
## [param condition] 实际条件。[param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
