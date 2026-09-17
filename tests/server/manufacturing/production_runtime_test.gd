extends SceneTree

class RejectingRepository extends PlayerStateRepository:
	var writes := 0
	## 注入可恢复的磁盘错误，不接触实际文件。
	## [param _state] 不会被写入的候选。
	## [param _expected_revision] 预期仓储版本。
	## 返回故障结果。
	func save_player(_state: PlayerStateRecord, _expected_revision: int) -> DomainResult:
		writes += 1
		return DomainResult.failure(&"test.disk_failure", "模拟磁盘写入失败")

var checks := 0
var failures: Array[String] = []
var messages: Array[Dictionary] = []
var server: AuthoritativeServer
var config := DedicatedServerConfig.new()
var recipe: ManufacturingRecipe
var peer := 94
var entity_id := ""


## 延迟初始化真实服务器与隔离存档。
func _initialize() -> void:
	call_deferred("_run")


## 验证服务端倒计时、长帧上限、失败退避、重启、快速重连和真实出口切图。
func _run() -> void:
	config.network_enabled = false
	config.map_config_path = "res://content/glory/map_definitions/glory_nft_bl_factory1.json"
	config.default_spawn = Vector2(1104, 420)
	config.autosave_interval_seconds = 100000
	config.player_state_store_path = "res://.godot/production-runtime-%d.json" % Time.get_ticks_usec()
	if not _boot():
		quit(1)
		return
	for candidate: ManufacturingRecipe in server.manufacturing_service._recipe_book.recipes_for_station("refining"):
		if server.manufacturing_service._item_catalog.display_name(candidate.product_definition_id) == "铁": recipe = candidate
	_check(recipe != null, "真实提炼配方")
	var mapper: PlayerStateMapper = server.manufacturing_service._mapper
	var player: Player = mapper.to_domain(_state()).value
	player.skills = SkillBook.new({"refining": 100})
	player.inventory = Inventory.new()
	_check(player.inventory.add_reward(server.manufacturing_service._item_catalog.create(recipe.materials[0].definition_id, {"instance_id": "ore", "quantity": 90}).value).is_ok, "测试矿石")
	_check(server.autosave_service.commit_player_state(entity_id, mapper.to_record(player).value).is_ok, "隔离材料提交")
	var start := {"type": "start_production", "station_id": "refining", "recipe_id": recipe.recipe_id,
		"cycles": 4, "speed": 2, "inventory_revision": _state().inventory_revision, "production_revision": 0}
	_check(server.handle_peer_player_panel_command(peer, start).ok, "权威开始")
	server.advance_simulation(1.0, 1001)
	var queried := server.handle_peer_player_panel_command(peer, {"type": "query_production"})
	_check(queried.ok and queried.value.manufacturing.production.order.remaining_milliseconds == 1000, "真实时钟已等一秒")
	_check(_quantity(recipe.product_definition_id) == 0 and _quantity(recipe.materials[0].definition_id) == 90, "等待不产生物品也不扣料")
	server._save_all_persistent_players()
	server.free()
	if not _boot():
		quit(1)
		return
	_check(_state().production.order.paused and _state().production.order.remaining_milliseconds == 1000, "重启保存剩余时长并暂停")
	server.advance_simulation(3.0, 1002)
	_check(_quantity(recipe.product_definition_id) == 0, "重启离线时间不产出")
	_check(_control("resume_production").ok, "重启后手动继续")
	server.advance_simulation(0.5, 1003)
	_check(_quantity(recipe.product_definition_id) == 0, "恢复仍需剩余等待")
	server.advance_simulation(0.6, 1004)
	_check(_state().production.order.completed == 1 and _quantity(recipe.product_definition_id) == 2, "首轮真实入账")
	_check(_quantity(recipe.materials[0].definition_id) == 70, "首轮真实耗料")
	server.advance_simulation(6.0, 1005)
	_check(_state().production.order.completed == 2 and _quantity(recipe.product_definition_id) == 4, "长帧只结算一轮")
	var original_repository := server.autosave_service._repository
	var failing := RejectingRepository.new()
	server.autosave_service._repository = failing
	var before := _state()
	server.advance_simulation(2.0, 1006)
	_check(failing.writes == 1 and _state().production.order.completed == 2 and _state().inventory_revision == before.inventory_revision, "写盘失败不能推进轮次或背包")
	_check(_quantity(recipe.product_definition_id) == 4 and _quantity(recipe.materials[0].definition_id) == 50, "写盘失败保持两侧数量")
	server.advance_simulation(0.2, 1007)
	_check(failing.writes == 1, "失败后退避不每帧写盘")
	_check(messages.any(func(message: Dictionary) -> bool: return message.get("type") == "player_panels" and not bool(message.get("result", {}).get("ok", true))), "失败发送实际错误")
	server.autosave_service._repository = original_repository
	server.advance_simulation(1.0, 1008)
	_check(_state().production.order.completed == 3 and _quantity(recipe.product_definition_id) == 6, "恢复后仅入账一次")
	_check(not server.handle_peer_player_panel_command(peer, start).ok, "最初开始意图不能重发")
	var session := server.sessions.session_for_peer(peer)
	var token := session.reconnect_token
	server.advance_simulation(0.25, 1009)
	_check(server.disconnect_session(peer, 1010).ok and _state().production.order.paused, "断线立即暂停")
	peer = 95
	_check(server.open_session(peer, {"protocol_version": config.protocol_version, "content_version": config.content_version, "reconnect_token": token}, 1011).ok, "快速重连")
	server.advance_simulation(3.0, 1012)
	_check(_state().production.order.completed == 3 and _quantity(recipe.product_definition_id) == 6, "快速重连不自动继续")
	_check(_control("resume_production").ok, "重连后继续")
	server.autosave_service._repository = failing
	_check(server.disconnect_session(peer, 1012).ok, "写入故障时仍可断线")
	peer = 96
	_check(server.open_session(peer, {"protocol_version": config.protocol_version, "content_version": config.content_version, "reconnect_token": token}, 1012).ok, "故障期间快速重连")
	server.autosave_service._repository = original_repository
	server.advance_simulation(3.0, 1012)
	_check(_state().production.order.paused and _quantity(recipe.product_definition_id) == 6, "断线暂停写入失败后重连仍只重试暂停")
	_check(_control("resume_production").ok, "故障恢复后可显式继续")
	_test_map_change()
	var canceled := _control("cancel_production", true)
	_check(canceled.ok and _state().production.order == null and _quantity(recipe.product_definition_id) == 6, "野外取消保留已完成成果")
	_check(server._production_runtime._clocks.is_empty(), "取消清除运行时计时器")
	server.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	for failure in failures: push_error(failure)
	print("Production runtime: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)


## 从提炼厂原出口经过正式切图处理器离开，验证在下一轮之前暂停。
func _test_map_change() -> void:
	var session := server.sessions.session_for_peer(peer)
	var source := server.map_registry.instance_by_id(session.map_instance_id)
	var transitions: Array[MapTransition] = source.definition.enabled_transitions()
	_check(not transitions.is_empty(), "提炼厂存在原出口")
	if transitions.is_empty(): return
	var transition := transitions[0]
	var entity: AuthoritativeEntity = source.entities[entity_id]
	entity.position = transition.approach_point if not transition.approach_point.is_zero_approx() else transition.source_anchor
	var changed := server.handle_peer_map_transition(peer, {"map_instance_id": session.map_instance_id,
		"transition_id": String(transition.transition_id), "destination_entry_number": transition.destination_entry_number, "input_sequence": 1})
	_check(changed.ok, "正式出口切图")
	_check(_state().production.order.paused, "正式切图立即暂停不依赖下一次时钟")
	server.advance_simulation(0.25, 1013)
	_check(_state().production.order.paused and _state().production.order.completed == 3, "切图暂停且没有多产出")
	_check(not _control("resume_production").ok, "新地图不可继续原订单")


## 启动新服务器实例并连接同一隔离人物，不读取日常存档。
## 返回初始化和登录是否成功。
func _boot() -> bool:
	server = AuthoritativeServer.new()
	var result := server.initialize(config)
	_check(result.ok, "服务器初始化：" + String(result.get("message", "")))
	if not result.ok: return false
	result = server.open_session(peer, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000)
	_check(result.ok, "服务器登录")
	if not result.ok: return false
	entity_id = server.sessions.session_for_peer(peer).entity_id
	server.server_message_generated.connect(func(_peer_id: int, message: Dictionary) -> void: messages.append(message.duplicate(true)))
	return true


## 读取服务器拥有的当前记录副本。
## 返回测试人物记录。
func _state() -> PlayerStateRecord:
	return server.autosave_service.state_for(entity_id)


## 从当前已提交记录统计实际物品。
## [param definition_id] 原料或产物定义。
## 返回数量。
func _quantity(definition_id: String) -> int:
	var amount := 0
	for stack: InventoryStackRecord in _state().inventory_stacks:
		if stack.item_definition_id == definition_id: amount += stack.quantity
	return amount


## 经真实人物命令处理器提交订单控制，自动存档版本不参与此意图。
## [param kind] 暂停、继续或取消。
## [param confirm] 是否确认取消。
## 返回权威结果。
func _control(kind: String, confirm: bool = false) -> Dictionary:
	return server.handle_peer_player_panel_command(peer, {"type": kind, "production_revision": _state().production.revision, "confirm_cancel": confirm})


## 累计服务器时序及真实保存断言。
## [param condition] 预期条件。
## [param label] 故障标签。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
