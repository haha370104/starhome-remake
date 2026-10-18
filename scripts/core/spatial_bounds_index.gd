class_name SpatialBoundsIndex
extends RefCounted

const CELL_SIZE := 128.0
var _bounds: Dictionary[String, Rect2] = {}
var _cells: Dictionary[Vector2i, Dictionary] = {}
var _order: Dictionary[String, int] = {}
var _sequence := 0


## 将实际可点击矩形登记到所有覆盖网格，原地更新不会反复重建桶。
## [param identity] 稳定实体编号。[param bounds] 世界坐标矩形。
func update(identity: String, bounds: Rect2) -> void:
	if _bounds.get(identity, Rect2()) == bounds and _bounds.has(identity): return
	var order: int = _order.get(identity, _sequence)
	if not _order.has(identity): _sequence += 1
	remove(identity)
	_bounds[identity] = bounds.abs()
	_order[identity] = order
	for cell: Vector2i in _covered_cells(bounds.abs()):
		if not _cells.has(cell): _cells[cell] = {}
		_cells[cell][identity] = true


## 删除实体覆盖的桶及顺序记录。
## [param identity] 要移除的实体身份。
func remove(identity: String) -> void:
	if not _bounds.has(identity): return
	for cell: Vector2i in _covered_cells(_bounds[identity]):
		_cells[cell].erase(identity)
		if _cells[cell].is_empty(): _cells.erase(cell)
	_bounds.erase(identity)
	_order.erase(identity)


## 仅查询鼠标所在网格，保持原登记顺序供同高度视图确定前后关系。
## [param point] 世界坐标。
## 返回粗筛编号，调用方继续原有精确命中逻辑。
func at_point(point: Vector2) -> Array[String]:
	var ids: Array[String] = []
	for identity: String in _cells.get(_cell(point), {}):
		if _bounds[identity].has_point(point): ids.append(identity)
	ids.sort_custom(func(left: String, right: String) -> bool: return _order[left] < _order[right])
	return ids


## 清除旧地图的所有空间和登记顺序状态。
func clear() -> void:
	_bounds.clear()
	_cells.clear()
	_order.clear()
	_sequence = 0


## 枚举矩形覆盖的桶，允许负坐标及跨桶的大型图像。
## [param bounds] 已规范化矩形。
## 返回全部相交桶。
func _covered_cells(bounds: Rect2) -> Array[Vector2i]:
	var first := _cell(bounds.position)
	var last := _cell(bounds.end)
	var result: Array[Vector2i] = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1): result.append(Vector2i(x, y))
	return result


## 以向下取整映射负世界坐标。
## [param point] 世界坐标。
## 返回网格键。
func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))
