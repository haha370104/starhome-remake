class_name GroundLootWorldController
extends Node

const GroundLootWorldViewScript := preload(
	"res://scripts/client/presentation/combat/ground_loot_world_view.gd"
)

var _world_parent: Node2D
var _catalog: ItemCatalog
var _items: Dictionary = {}
var _views: Dictionary = {}
var _hovered_loot_id := ""


## 绑定世界父节点并载入地面物品业务表现目录。
## [param world_parent] 与人物、怪物共享 Y 排序的活动世界节点。
## [param item_catalog] 同时为地面与背包组装物品实例的共享领域目录。
## 返回目录可用性；空世界或空目录返回 ERR_INVALID_PARAMETER。
func configure(world_parent: Node2D, item_catalog: ItemCatalog) -> Error:
	if world_parent == null or item_catalog == null:
		return ERR_INVALID_PARAMETER
	_world_parent = world_parent
	_catalog = item_catalog
	set_process(true)
	return OK


## 将权威战斗快照中的 ground_loot 投影为地面物品，并清理已拾取实例。
## [param combat_snapshot] 当前地图对本地玩家可见的完整战斗快照。
func apply_snapshot(combat_snapshot: Dictionary) -> void:
	var observed: Dictionary = {}
	var loot_value: Variant = combat_snapshot.get("ground_loot", [])
	if not loot_value is Array:
		loot_value = []
	for raw_loot: Variant in loot_value:
		if not raw_loot is Dictionary:
			continue
		var loot: Dictionary = raw_loot
		var loot_id := String(loot.get("loot_id", ""))
		var definition_id := String(loot.get("item_definition_id", ""))
		if loot_id.is_empty() or definition_id.is_empty():
			continue
		observed[loot_id] = true
		var view: GroundLootWorldView = _views.get(loot_id)
		if view == null:
			var created := _catalog.create(definition_id, {
				"instance_id": loot_id,
				"quantity": int(loot.get("quantity", 1)),
			})
			if not created.is_ok:
				continue
			var item: GameItem = created.value
			view = GroundLootWorldViewScript.new()
			view.name = "GroundLoot_%s" % loot_id.replace(".", "_")
			_world_parent.add_child(view)
			if view.configure(item, loot) != OK:
				view.queue_free()
				continue
			_items[loot_id] = item
			_views[loot_id] = view
		else:
			var item: GameItem = _items.get(loot_id)
			if item != null:
				item.quantity = maxi(1, int(loot.get("quantity", item.quantity)))
				view.apply_snapshot(item, loot)
	for existing_id: String in _views.keys():
		if observed.has(existing_id):
			continue
		var stale: GroundLootWorldView = _views[existing_id]
		stale.queue_free()
		_views.erase(existing_id)
		_items.erase(existing_id)
		if _hovered_loot_id == existing_id:
			_hovered_loot_id = ""


## 查询原图、发光边缘或可见名称命中的最前方掉落，与悬停共用拾取范围。
## [param world_position] 鼠标对应的世界坐标。
## 返回 loot_id；没有命中时返回空字符串。
func loot_at(world_position: Vector2) -> String:
	var selected := ""
	var selected_y := -INF
	for loot_id: String in _views:
		var view: GroundLootWorldView = _views[loot_id]
		if view.contains_pickup_point(world_position) and view.position.y >= selected_y:
			selected = loot_id
			selected_y = view.position.y
	return selected


## 立即移除已收到权威拾取成功事件的掉落视图。
## [param loot_id] 服务端确认删除的掉落实例标识。
func remove_loot(loot_id: String) -> void:
	var view: GroundLootWorldView = _views.get(loot_id)
	if view == null:
		return
	view.queue_free()
	_views.erase(loot_id)
	_items.erase(loot_id)
	if _hovered_loot_id == loot_id:
		_hovered_loot_id = ""


## 清理当前地图全部掉落表现，不改变任何权威数据。
func clear() -> void:
	for view: GroundLootWorldView in _views.values():
		view.queue_free()
	_views.clear()
	_items.clear()
	_hovered_loot_id = ""


## 统计当前活动掉落视图数量，供诊断和回归测试使用。
## 返回控制器索引中的视图数。
func active_view_count() -> int:
	return _views.size()


## 查询指定掉落实例的世界视图，供只读诊断和测试使用。
## [param loot_id] 掉落实例标识。
## 返回对应视图；不存在时返回 null。
func view_for_loot(loot_id: String) -> GroundLootWorldView:
	return _views.get(loot_id) as GroundLootWorldView


## 每帧执行 `_process`，根据鼠标世界坐标更新唯一悬浮高亮和名称提示。
## [param _delta] 当前渲染帧间隔；悬浮命中不依赖时间。
func _process(_delta: float) -> void:
	if _world_parent == null or not is_instance_valid(_world_parent):
		return
	var next_hovered := loot_at(_world_parent.get_global_mouse_position())
	if next_hovered == _hovered_loot_id:
		return
	var previous: GroundLootWorldView = _views.get(_hovered_loot_id)
	if previous != null:
		previous.set_hovered(false)
	_hovered_loot_id = next_hovered
	var current: GroundLootWorldView = _views.get(_hovered_loot_id)
	if current != null:
		current.set_hovered(true)
