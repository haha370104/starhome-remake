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


## 独立绑定世界生命周期与权威面板消息，关闭地图即释放果实节点。
## [param world] 活动世界。[param sortable] 共用深度排序层。[param catalog] 物品目录。
## [param session] 玩家命令入口。[param travel] 原子切图信号。[param hud] 交互提示。
func configure(world: ActiveWorldController, sortable: Node2D, catalog: ItemCatalog,
		session: PlayerPanelSession, travel: MapTravelController, hud: HallHud) -> void:
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
	_hud.show_system_message("打开当前地图，可选择采摘点自动前往；靠近后左键果实或名称采摘。")


## 原子切图开始时移除旧果实，异步旧回复不能复活旧地图。
func clear() -> void:
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


## 每帧以当前相机转换后的世界鼠标位置更新悬浮；和点击共用命中，移动相机也不会残留高亮。
## [param _delta] 帧间隔，命中判定不依赖时间。
func _process(_delta: float) -> void:
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


## 发出目标身份和当前背包版本，地点、数量及奖励均由服务器决定。
## [param id] 当前选中果实身份。
func harvest(id: String) -> void:
	if _session == null: return
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
