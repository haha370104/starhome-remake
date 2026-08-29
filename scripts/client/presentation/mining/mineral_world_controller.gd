class_name MineralWorldController
extends Node

const MineralWorldViewScript := preload(
	"res://scripts/client/presentation/mining/mineral_world_view.gd"
)

var _world_parent: Node2D
var _definitions: Dictionary = {}
var _views: Dictionary = {}
var _hovered_source_id := ""


## 绑定活动地图的共享 Y 排序层和已解析的矿物表现清单。
func configure(world_parent: Node2D, manifest: Dictionary) -> Error:
	if world_parent == null or not manifest.get("definitions", {}) is Dictionary:
		return ERR_INVALID_PARAMETER
	_world_parent = world_parent
	_definitions = (manifest["definitions"] as Dictionary).duplicate(true)
	if _definitions.is_empty():
		return ERR_INVALID_DATA
	set_process(true)
	return OK


## 将服务器完整矿源快照投影为世界节点，并移除已耗尽或离图矿点。
func apply_snapshot(combat_snapshot: Dictionary) -> void:
	var observed: Dictionary = {}
	var source_value: Variant = combat_snapshot.get("mine_sources", [])
	if not source_value is Array:
		source_value = []
	for raw_source: Variant in source_value:
		if not raw_source is Dictionary:
			continue
		var source: Dictionary = raw_source
		var source_id := String(source.get("source_id", ""))
		var mineral_id := String(source.get("mineral_id", ""))
		var presentation_value: Variant = _definitions.get(mineral_id)
		if source_id.is_empty() or not presentation_value is Dictionary:
			continue
		observed[source_id] = true
		var view: MineralWorldView = _views.get(source_id)
		if view == null:
			view = MineralWorldViewScript.new()
			view.name = "Mineral_%s" % source_id.replace(".", "_")
			_world_parent.add_child(view)
			if view.configure(source, presentation_value) != OK:
				view.queue_free()
				continue
			_views[source_id] = view
		else:
			view.apply_snapshot(source)
	for existing_id: String in _views.keys():
		if observed.has(existing_id):
			continue
		var stale: MineralWorldView = _views[existing_id]
		stale.queue_free()
		_views.erase(existing_id)
		if _hovered_source_id == existing_id:
			_hovered_source_id = ""


## 返回坐标命中的最前方矿源标识。
func source_at(world_position: Vector2) -> String:
	var selected := ""
	var selected_y := -INF
	for source_id: String in _views:
		var view: MineralWorldView = _views[source_id]
		if view.contains_world_point(world_position) and view.position.y >= selected_y:
			selected = source_id
			selected_y = view.position.y
	return selected


## 返回矿源的权威脚点；不存在时返回非有限坐标。
func source_position(source_id: String) -> Vector2:
	var view: MineralWorldView = _views.get(source_id)
	return view.position if view != null else Vector2.INF


## 清除旧地图的全部矿物表现。
func clear() -> void:
	for view: MineralWorldView in _views.values():
		view.queue_free()
	_views.clear()
	_hovered_source_id = ""


## 返回当前活动矿点数，供诊断和回归测试读取。
func active_view_count() -> int:
	return _views.size()


## 返回指定矿点视图，供只读诊断和测试使用。
func view_for_source(source_id: String) -> MineralWorldView:
	return _views.get(source_id) as MineralWorldView


## 按鼠标世界坐标维护唯一悬浮矿源。
func _process(_delta: float) -> void:
	if _world_parent == null or not is_instance_valid(_world_parent):
		return
	var next_hovered := source_at(_world_parent.get_global_mouse_position())
	if next_hovered == _hovered_source_id:
		return
	var previous: MineralWorldView = _views.get(_hovered_source_id)
	if previous != null:
		previous.set_hovered(false)
	_hovered_source_id = next_hovered
	var current: MineralWorldView = _views.get(_hovered_source_id)
	if current != null:
		current.set_hovered(true)

