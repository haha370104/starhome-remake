class_name BotanicalGardenController
extends Node

var plants: Array[WorldGardenPlant] = []
var _rules: BotanicalGardenCatalog
var _world: ActiveWorldController
var _root: Node2D
var _catalog: ItemCatalog
var _session: PlayerPanelSession
var _hud: HallHud
var _hovered_plant: WorldGardenPlant
var _mouse_position := Vector2.INF
var _movement: LocalPlayerController
var _travel: MapTravelController
var _pending_plant_id := ""
var _arrival_deadline := 0


## 独立绑定世界生命周期与权威面板消息，关闭地图即释放果实节点。
## [param world] 活动世界。[param sortable] 共用深度排序层。[param catalog] 物品目录。
## [param session] 玩家命令入口。[param travel] 原子切图信号。[param hud] 交互提示。
## [param movement] 唯一移动入口及权威到达位置。
func configure(world: ActiveWorldController, sortable: Node2D, catalog: ItemCatalog,
		session: PlayerPanelSession, travel: MapTravelController, hud: HallHud,
		movement: LocalPlayerController) -> void:
	var loaded := BotanicalGardenCatalog.load_default()
	if not loaded.is_ok:
		push_error(loaded.error_message)
		return
	_rules = loaded.value
	_world = world
	_root = sortable
	_catalog = catalog
	_session = session
	_hud = hud
	_movement = movement
	_travel = travel
	_movement.route_invalidated.connect(cancel_pending_harvest)
	_movement.route_finished.connect(_on_route_finished)
	_world.active_world_will_replace.connect(clear)
	travel.map_committed.connect(rebuild)
	_session.bundle_received.connect(apply_bundle)
	get_viewport().mouse_exited.connect(_on_mouse_exited)
	rebuild()


## 地图提交后创建当前地图的果实，并查询角色持久化冷却。
func rebuild() -> void:
	clear()
	if _rules == null or _world.definition == null or String(_world.definition.map_id) != _rules.map_id: return
	var points: Array[MapNavigationPoint] = []
	for plant: BotanicalGardenCatalog.Plant in _rules.plants:
		var view := WorldGardenPlant.new()
		if not view.configure(plant, _catalog):
			view.free()
			push_error("植物园果实素材缺失：" + plant.id)
			continue
		_root.add_child(view)
		plants.append(view)
		points.append(MapNavigationPoint.new(StringName("garden:" + plant.id), view.display_name,
			"采摘", plant.position, plant.position))
	_world.set_module_navigation_points(&"garden", StringName(_rules.map_id), points)
	_session.dispatch({"type": "query_garden"})


## 原子切图开始时移除旧果实，异步旧回复不能复活旧地图。
func clear() -> void:
	cancel_pending_harvest()
	_hovered_plant = null
	for plant: WorldGardenPlant in plants:
		plant.queue_free()
	plants.clear()
	if _world != null and _rules != null:
		_world.set_module_navigation_points(&"garden", StringName(_rules.map_id), [])


## 查找果实交互目标，不参与矿点、掉落或 NPC 的状态管理。
## [param position] 世界点击位置。
## 返回当前命中的果实或空值。
func plant_at(position: Vector2) -> WorldGardenPlant:
	var selected: WorldGardenPlant = null
	for plant: WorldGardenPlant in plants:
		if plant.hit_test(position) and (selected == null or plant.position.y >= selected.position.y): selected = plant
	return selected


## 记录视口内鼠标位置，避免依赖窗口外或不可见窗口的桌面鼠标坐标。
## [param event] 原始视口输入；GUI是否消费点击不改变光标位置。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion: _mouse_position = event.position


## 更新悬浮，并在本地抵达后等待权威位置也进入采摘范围。
## [param _delta] 帧间隔，命中判定不依赖时间。
func _process(_delta: float) -> void:
	if _arrival_deadline > 0: _try_harvest_after_arrival()
	if plants.is_empty() or not is_instance_valid(_root) or not _mouse_position.is_finite(): return
	update_hover(_root.get_canvas_transform().affine_inverse() * _mouse_position)


## 鼠标离开游戏视口时清除悬浮，保留独立的菜单选中状态。
func _on_mouse_exited() -> void:
	_mouse_position = Vector2.INF
	update_hover(Vector2.INF)


## 切换唯一悬浮目标，不改变菜单选中或权威成熟状态。
## [param world_position] 当前世界鼠标坐标。
func update_hover(world_position: Vector2) -> void:
	var next := plant_at(world_position)
	if next == _hovered_plant: return
	if is_instance_valid(_hovered_plant): _hovered_plant.set_hovered(false)
	_hovered_plant = next
	if _hovered_plant != null: _hovered_plant.set_hovered(true)


## 近处直接采摘，远处先请求可达路线；奖励和距离仍由服务器验证。
## [param id] 当前选中果实身份。
func harvest(id: String) -> void:
	cancel_pending_harvest()
	if _session == null or _world.definition == null or _travel.is_locked(): return
	if String(_world.definition.map_id) != _rules.map_id: return
	var plant := _rules.find(id)
	if plant == null: return
	if _within_range(plant):
		_send_harvest(id)
		return
	var target: Vector2 = _world.navigation.closest_reachable_position(_movement.position(), plant.position)
	if not target.is_finite() or target.distance_to(plant.position) > _rules.interaction_radius:
		_hud.show_system_message("无法走到这株植物附近")
		return
	_travel.selected_transition_id = &""
	var result := _movement.request_move(target)
	if not result.get("ok", false):
		_hud.show_system_message(String(result.get("message", "无法走到这株植物附近")))
		return
	_pending_plant_id = id
	_hud.show_status("正在前往采摘")


## 清除待采摘意图，不停止调用方刚设置的新路线。
func cancel_pending_harvest() -> void:
	_pending_plant_id = ""
	_arrival_deadline = 0


## 本地抵达后最多等待五秒权威位置确认，不依赖固定延迟猜测服务器进度。
func _on_route_finished() -> void:
	if _pending_plant_id.is_empty(): return
	_arrival_deadline = Time.get_ticks_msec() + 5000
	_try_harvest_after_arrival()


## 等待权威进入范围；超时或切图时取消，不持续重试采摘命令。
func _try_harvest_after_arrival() -> void:
	if _travel.is_locked():
		cancel_pending_harvest()
		return
	var plant := _rules.find(_pending_plant_id)
	if plant != null and _within_range(plant):
		var id := _pending_plant_id
		cancel_pending_harvest()
		_send_harvest(id)
	elif Time.get_ticks_msec() >= _arrival_deadline:
		cancel_pending_harvest()
		_hud.show_system_message("尚未到达采摘范围，请重新选择植物")


## 同时检查表现脚点和权威脚点，避免预测先到导致服务端拒绝。
## [param plant] 受控目录中的目标植物。
## 返回两端均处于采摘半径内时为真。
func _within_range(plant: BotanicalGardenCatalog.Plant) -> bool:
	return _movement.position().distance_to(plant.position) <= _rules.interaction_radius \
		and _movement.confirmed_position().distance_to(plant.position) <= _rules.interaction_radius


## 到达后读取最新背包版本，只发出一次采摘命令。
## [param id] 当前地图的目标植物身份。
func _send_harvest(id: String) -> void:
	_session.dispatch({"type": "harvest_garden", "plant_id": id,
		"inventory_revision": _session.current_player.inventory.revision})


## 只接收当前地图的权威成熟状态，并发布成功提示。
## [param bundle] 共用人物命令返回的辅助投影。
func apply_bundle(bundle: Dictionary) -> void:
	var garden: Variant = bundle.get("garden")
	if not garden is Dictionary or _world.definition == null or garden.get("map_id") != String(_world.definition.map_id): return
	for row: Dictionary in garden.get("plants", []):
		for plant: WorldGardenPlant in plants:
			if plant.plant_id == row.get("plant_id"): plant.apply_regrowth(int(row.get("remaining_seconds", 0)))
	var message := String(garden.get("message", ""))
	if not message.is_empty(): _hud.show_system_message(message)
