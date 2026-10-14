extends SceneTree

var checks := 0
var failures: Array[String] = []


## 使用真实服务器检验窄端口、路径执行及提供器协议。
func _initialize() -> void:
	call_deferred("_run")


## 从城市正式入口走入植物园，验证会话隔离、自动采摘和冷却。
func _run() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.dynamic_blocking_enabled = false
	config.map_config_path = "res://data/maps/yian_harbor_city.json"
	config.default_spawn = Vector2(2351, 333)
	config.player_state_store_path = "user://ai-authority-%d.json" % Time.get_ticks_usec()
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "权威服务器初始化")
	var world := AiAuthorityAdapter.new(server, 1500)
	var opened := world.open_actor("gardener")
	_check(opened.is_ok, "创建独立AI")
	var actor: AiPlayerActor = opened.value
	var human := server.open_session(2, {"protocol_version": config.protocol_version, "content_version": config.content_version})
	_check(human.ok and human.value.session.entity_id == "player.1", "AI先启动不占真人身份")
	var view: AiPlayerObservation = world.observe(actor).value
	_check(not JSON.stringify(view.to_dictionary()).contains("session_token"), "观察无会话令牌")
	var forged := AiPlayerActor.new()
	forged.peer_id = 2
	forged.entity_id = "player.1"
	_check(not world.move(forged, Vector2.ZERO).is_ok, "不能通过端口控制真人")
	var executor := AiPlayerExecutor.new(world)
	var travel: AiPlayerAction = AiPlayerAction.parse({"kind": "travel", "target_id": "enter_botanical_garden"}).value
	_check(view.find("travel", travel.target_id) != null, "观察包含真实入口")
	var result := _execute(server, world, executor, actor, travel)
	_check(result.is_ok, "经正式切图入口进入植物园：" + result.error_message)
	view = world.observe(actor).value
	_check(view.map_id == server.garden_service.rules.map_id, "AI位置属于真实植物园")
	var chosen: AiPlayerObservation.Target
	var nearest := INF
	for target: AiPlayerObservation.Target in view.targets.get("harvest", []):
		if view.position.distance_to(target.position) < nearest:
			nearest = view.position.distance_to(target.position)
			chosen = target
	_check(chosen != null, "附近植物可被观察")
	if chosen != null:
		var harvest: AiPlayerAction = AiPlayerAction.parse({"kind": "harvest", "target_id": chosen.id}).value
		var item_id := server.garden_service.rules.find(chosen.id).item_id
		var before := _amount(server, actor, item_id)
		_check(nearest > 150, "采摘从距离外开始")
		result = _execute(server, world, executor, actor, harvest)
		_check(result.is_ok, "自动走近采摘：" + result.error_message)
		_check(_amount(server, actor, item_id) == before + 1, "正式事务入账一份果实")
		_check(not _execute(server, world, executor, actor, harvest).is_ok, "冷却不可重复刷取")
	var forged_item: AiPlayerAction = AiPlayerAction.parse({"kind": "panel", "panel_command_json": '{"type":"use_inventory_item","instance_id":"other-player-item"}'}).value
	_check(not world.perform(actor, forged_item, null).is_ok, "物品所有权由权威背包拒绝")
	var valid_response := {"status": "completed", "output": [{"type": "function_call", "name": "choose_action", "arguments": '{"kind":"wait"}'}]}
	_check(AiResponsesProvider.parse_response(valid_response).is_ok, "解析Responses函数调用")
	valid_response.output.append(valid_response.output[0].duplicate())
	_check(not AiResponsesProvider.parse_response(valid_response).is_ok, "拒绝同一次多行动")
	_check(not AiResponsesProvider.parse_response({"status": "incomplete", "output": []}).is_ok, "截断输出不可执行")
	var memory := AiPlayerMemory.new()
	var directory := "user://ai-authority-memory-%d" % Time.get_ticks_usec()
	_check(memory.start(directory), "异步记忆线程")
	actor.memory = "下一次探索"
	actor.remember(DomainResult.ok(), 1)
	memory.save(actor)
	_check(memory.close().is_ok, "退出排空记忆")
	actor.memory = ""
	memory.restore(actor)
	_check(actor.memory == "下一次探索", "恢复独立角色计划")
	_check(world.close_actor(actor).is_ok, "正常释放AI")
	_check(server.sessions.session_for_peer(2) != null, "关闭AI不关闭真人")
	server._save_all_persistent_players()
	server.free()
	print("AI authority: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 推进真实地图模拟直到自动接近行动完成；不伪造实体位置。
## [param server] 权威服务。[param world] 窄端口。[param executor] 行动器。[param actor] 自身会话。[param action] 合法动作。
## 返回动作结果或超时。
func _execute(server: AuthoritativeServer, world: AiWorldPort, executor: AiPlayerExecutor, actor: AiPlayerActor, action: AiPlayerAction) -> DomainResult:
	var view: AiPlayerObservation = world.observe(actor).value
	executor.begin(actor, action, view, 0)
	for index in 61:
		view = world.observe(actor).value
		var result := executor.step(actor, view, index * 500)
		if result != null: return result
		server.advance_simulation(0.5)
	return DomainResult.failure(&"test.timeout", "超时")


## 读取实际背包数量作为事务依据。
## [param server] 权威服务。[param actor] 自身会话。[param id] 物品定义。
## 返回存档聚合内的数量。
func _amount(server: AuthoritativeServer, actor: AiPlayerActor, id: String) -> int:
	var amount := 0
	for stack: InventoryStackRecord in server.autosave_service.state_for(actor.entity_id).inventory_stacks:
		if stack.item_definition_id == id: amount += stack.quantity
	return amount


## 汇总正式行为断言。
## [param condition] 实际条件。[param message] 预期说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
