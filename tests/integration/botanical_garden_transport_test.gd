extends SceneTree

var _hall: Node2D
var checks := 0
var failures: Array[String] = []


## 经真实进程内传输检查正常入口与采摘，不替换客户端命令分派器。
func _initialize() -> void:
	call_deferred("_run")


## 从城市入口进入植物园，通过地图导航靠近后采摘，并检查实际背包与冷却回包。
func _run() -> void:
	_hall = load("res://scenes/main_hall.tscn").instantiate()
	_hall.multiplayer_connect_automatically = false
	root.add_child(_hall)
	await process_frame
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = "res://data/maps/yian_harbor_city.json"
	config.default_spawn = Vector2(2351, 333)
	config.dynamic_blocking_enabled = false
	config.player_state_store_path = "user://garden-transport-%d.json" % Time.get_ticks_usec()
	var session: ClientMultiplayerSession = _hall.multiplayer_presenter.session
	_check(session.network_adapter.configure_in_process_server(config), "使用正式权威服务器")
	_hall.map_travel._initial_authoritative_world_ready = false
	_check(session.connect_to_server("in-process", 0) == OK, "客户端建立会话")
	if not await _wait_for(func() -> bool: return _hall.map_travel._initial_authoritative_world_ready \
		and _hall.active_world_controller.definition.map_id == &"yian_harbor_city", 10.0):
		await _finish()
		return
	_check(_hall.active_world_controller.definition.map_id == &"yian_harbor_city", "从城市入口开始")
	_hall.map_travel.selected_transition_id = &"enter_botanical_garden"
	_hall.map_travel.try_begin_nearby_map_transition()
	if not await _wait_for(func() -> bool: return _hall.interactions.garden.plants.size() == 15 \
		and _hall.interactions.garden.plants.all(func(plant: WorldGardenPlant) -> bool: return plant._known), 15.0):
		await _finish()
		return
	var garden: BotanicalGardenController = _hall.interactions.garden
	_check(garden.plants.all(func(plant: WorldGardenPlant) -> bool: return plant._sprite.visible), "真实切图回包显示全部成熟果实")
	var point: MapNavigationPoint = null
	var plant: WorldGardenPlant = null
	var nearest := INF
	for candidate: WorldGardenPlant in garden.plants:
		var distance: float = candidate.position.distance_to(_hall.world_view.player.position)
		if distance < nearest:
			nearest = distance
			plant = candidate
	for candidate: MapNavigationPoint in _hall.active_world_controller.navigation_points():
		if candidate.id == StringName("garden:" + plant.plant_id): point = candidate
	_check(point != null, "正式地图列表提供采摘目的地")
	if point == null:
		await _finish()
		return
	_hall.hud.map_navigation_requested.emit(point.destination, point.id)
	if not await _wait_for(func() -> bool: return not _hall.local_player_controller.has_active_route(), 30.0):
		await _finish()
		return
	_check(_hall.world_view.player.position.distance_to(plant.position) <= 150.0, "地图导航走到权威采摘距离内")
	var item_id := garden._rules.find(plant.plant_id).item_id
	var before := _amount(item_id)
	_hall.interactions.show_npc_popup(plant)
	_hall.hud.npc_action_requested.emit("harvest_garden")
	_check(await _wait_for(func() -> bool: return _amount(item_id) == before + 1, 3.0), "实际通信后果实入背包")
	_check(not plant._sprite.visible and plant.status_label.text.contains("生长中"), "采摘回复同步隐藏果实和更新成熟状态")
	garden.harvest(plant.plant_id)
	await process_frame
	_check(_amount(item_id) == before + 1, "冷却期间重复请求不发奖")
	await _finish()


## 等待真实异步链路，不手工发布地图完成或采摘结果信号。
## [param predicate] 实际可观察状态。[param timeout] 最大墙钟等待秒数。
## 返回状态是否在期限内出现，并记录超时失败。
func _wait_for(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not predicate.call():
		if Time.get_ticks_msec() > deadline:
			_check(false, "真实链路等待超时")
			return false
		await process_frame
	return true


## 汇总当前权威投影中的指定物品数量。
## [param item_id] 采摘产物稳定身份。
## 返回背包所有堆叠的数量合计。
func _amount(item_id: String) -> int:
	var amount := 0
	for item: GameItem in _hall.panel_session.current_player.inventory.items():
		if item.definition_id == item_id: amount += item.quantity
	return amount


## 释放真实客户端及其内嵌服务器，并输出所有失败。
func _finish() -> void:
	_hall.queue_free()
	await process_frame
	print("Garden transport: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 记录实际断言结果。
## [param condition] 实际条件。[param message] 预期行为。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
