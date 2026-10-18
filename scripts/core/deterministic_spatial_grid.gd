class_name DeterministicSpatialGrid
extends RefCounted

var cell_size := 256.0
var _cells: Dictionary = {}
var _positions: Dictionary = {}
var _entity_cells: Dictionary = {}


## 创建独立空间索引。
## [param requested_cell_size] 网格边长，默认 256 像素。
func _init(requested_cell_size := 256.0) -> void:
	configure(requested_cell_size)


## 设置网格尺寸并清空旧位置。
## [param requested_cell_size] 必须为有限正数的网格边长。
## 返回是否成功；非法尺寸不改变现有索引。
func configure(requested_cell_size: float) -> bool:
	if requested_cell_size <= 0.0 or not is_finite(requested_cell_size):
		return false
	cell_size = requested_cell_size
	clear()
	return true


## 移除所有实体和网格桶。
func clear() -> void:
	_cells.clear()
	_positions.clear()
	_entity_cells.clear()


## 登记实体的唯一位置。
## [param entity_id] 非空且尚未登记的实体编号。
## [param position] 有限世界坐标。
## 返回登记是否成功。
func register(entity_id: String, position: Vector2) -> bool:
	if entity_id.is_empty() or not position.is_finite() or _positions.has(entity_id):
		return false
	_positions[entity_id] = position
	var cell := cell_for_position(position)
	_entity_cells[entity_id] = cell
	_add_to_cell(entity_id, cell)
	return true


## 更新实体坐标，并在跨格时迁移桶归属。
## [param entity_id] 已登记的实体编号。
## [param position] 新的有限世界坐标。
## 返回更新是否成功。
func update(entity_id: String, position: Vector2) -> bool:
	if not _positions.has(entity_id) or not position.is_finite():
		return false
	var previous_cell: Vector2i = _entity_cells[entity_id]
	var next_cell := cell_for_position(position)
	_positions[entity_id] = position
	if previous_cell != next_cell:
		_remove_from_cell(entity_id, previous_cell)
		_entity_cells[entity_id] = next_cell
		_add_to_cell(entity_id, next_cell)
	return true


## 刷新实体坐标及网格归属。
## [param entity_id] 已登记的实体编号。
## [param position] 新的有限世界坐标。
## 返回刷新是否成功。
func refresh_cell(entity_id: String, position: Vector2) -> bool:
	if not _positions.has(entity_id) or not position.is_finite():
		return false
	var previous_cell: Vector2i = _entity_cells[entity_id]
	var next_cell := cell_for_position(position)
	_positions[entity_id] = position
	if previous_cell == next_cell:
		return true
	_remove_from_cell(entity_id, previous_cell)
	_entity_cells[entity_id] = next_cell
	_add_to_cell(entity_id, next_cell)
	return true


## 删除实体及其桶内索引。
## [param entity_id] 要删除的实体编号。
## 返回是否删除了已有实体。
func remove(entity_id: String) -> bool:
	if not _positions.has(entity_id):
		return false
	var cell: Vector2i = _entity_cells[entity_id]
	_remove_from_cell(entity_id, cell)
	_positions.erase(entity_id)
	_entity_cells.erase(entity_id)
	return true


## 查询实体是否已登记。
## [param entity_id] 待查询的实体编号。
## 返回索引是否包含此实体。
func contains(entity_id: String) -> bool:
	return _positions.has(entity_id)


## 读取实体登记的世界坐标。
## [param entity_id] 待查询的实体编号。
## 返回坐标；不存在时返回无限向量。
func position_for(entity_id: String) -> Vector2:
	return _positions.get(entity_id, Vector2.INF)


## 将世界坐标映射到网格，负坐标向下取整。
## [param position] 世界坐标。
## 返回整数网格坐标。
func cell_for_position(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))


## 筛选圆形区域内的实体，边界包含在内。
## [param center] 圆心世界坐标。
## [param radius] 有限非负半径。
## 返回按编号排序的精确命中结果。
func query_circle(center: Vector2, radius: float) -> Array[String]:
	if not center.is_finite() or radius < 0.0 or not is_finite(radius):
		return []
	var candidate_ids := query_aabb(
		center - Vector2(radius, radius),
		center + Vector2(radius, radius),
	)
	var radius_squared := radius * radius
	var result: Array[String] = []
	for entity_id: String in candidate_ids:
		if _positions[entity_id].distance_squared_to(center) <= radius_squared:
			result.append(entity_id)
	return result


## 筛选轴对齐矩形内的实体。
## [param minimum] 一个对角点。
## [param maximum] 另一个对角点，可与前者反向。
## 返回按编号排序的精确命中结果。
func query_aabb(minimum: Vector2, maximum: Vector2) -> Array[String]:
	var result: Array[String] = []
	var candidate_ids := query_aabb_candidates(minimum, maximum)
	if candidate_ids.is_empty():
		return result
	var lower := Vector2(minf(minimum.x, maximum.x), minf(minimum.y, maximum.y))
	var upper := Vector2(maxf(minimum.x, maximum.x), maxf(minimum.y, maximum.y))
	for entity_id: String in candidate_ids:
		var position: Vector2 = _positions[entity_id]
		if position.x < lower.x or position.x > upper.x \
			or position.y < lower.y or position.y > upper.y:
			continue
		result.append(entity_id)
	return result


## 收集矩形覆盖网格中的候选实体，由调用方继续精确碰撞判定。
## [param minimum] 一个对角点。
## [param maximum] 另一个对角点。
## 返回稳定排序且不重复的候选编号。
func query_aabb_candidates(minimum: Vector2, maximum: Vector2) -> Array[String]:
	if not minimum.is_finite() or not maximum.is_finite():
		return []
	var lower := Vector2(minf(minimum.x, maximum.x), minf(minimum.y, maximum.y))
	var upper := Vector2(maxf(minimum.x, maximum.x), maxf(minimum.y, maximum.y))
	var minimum_cell := cell_for_position(lower)
	var maximum_cell := cell_for_position(upper)
	var candidate_ids: Dictionary = {}
	for cell_y in range(minimum_cell.y, maximum_cell.y + 1):
		for cell_x in range(minimum_cell.x, maximum_cell.x + 1):
			var bucket: Dictionary = _cells.get(Vector2i(cell_x, cell_y), {})
			for entity_id: String in bucket:
				candidate_ids[entity_id] = true
	var result: Array[String] = []
	for raw_entity_id: Variant in candidate_ids:
		result.append(String(raw_entity_id))
	result.sort()
	return result


## 查询索引内的全部实体。
## 返回按编号排序的实体编号。
func query_all() -> Array[String]:
	var result: Array[String] = []
	for raw_entity_id: Variant in _positions:
		result.append(String(raw_entity_id))
	result.sort()
	return result


## 将实体放入指定网格桶。
## [param entity_id] 实体编号。
## [param cell] 目标网格坐标。
func _add_to_cell(entity_id: String, cell: Vector2i) -> void:
	var bucket: Dictionary = _cells.get(cell, {})
	bucket[entity_id] = true
	_cells[cell] = bucket


## 移除桶内实体，并回收空桶。
## [param entity_id] 实体编号。
## [param cell] 原网格坐标。
func _remove_from_cell(entity_id: String, cell: Vector2i) -> void:
	if not _cells.has(cell):
		return
	var bucket: Dictionary = _cells[cell]
	bucket.erase(entity_id)
	if bucket.is_empty():
		_cells.erase(cell)
	else:
		_cells[cell] = bucket
