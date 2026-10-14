class_name BotanicalGardenController
extends Node

var plants: Array[WorldGardenPlant] = []
var _rules: BotanicalGardenCatalog
var _world: ActiveWorldController
var _root: Node2D
var _catalog: ItemCatalog
var _session: PlayerPanelSession
var _hud: HallHud


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
	rebuild()


## 地图提交后创建当前地图的果实，并查询角色持久化冷却。
func rebuild() -> void:
	clear()
	if _rules == null or _world.definition == null or String(_world.definition.map_id) != _rules.map_id: return
	for plant: BotanicalGardenCatalog.Plant in _rules.plants:
		var view := WorldGardenPlant.new()
		if not view.configure(plant, _catalog):
			view.free()
			push_error("植物园果实素材缺失：" + plant.id)
			continue
		_root.add_child(view)
		plants.append(view)
	_session.dispatch({"type": "query_garden"})


## 原子切图开始时移除旧果实，异步旧回复不能复活旧地图。
func clear() -> void:
	for plant: WorldGardenPlant in plants:
		plant.queue_free()
	plants.clear()


## 查找果实交互目标，不参与矿点、掉落或 NPC 的状态管理。
## [param position] 世界点击位置。
## 返回当前命中的果实或空值。
func plant_at(position: Vector2) -> WorldGardenPlant:
	for plant: WorldGardenPlant in plants:
		if plant.hit_test(position): return plant
	return null


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
