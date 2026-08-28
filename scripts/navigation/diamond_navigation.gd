class_name DiamondNavigation
extends RefCounted

const DEFAULT_GRID_SIZE := Vector2i(35, 280)
const DEFAULT_CELL_SIZE := Vector2(48.0, 12.0)
const LINE_OF_SIGHT_SAMPLE_STEP := 3.0

var data := PackedByteArray()
var graph := AStar2D.new()
var grid_size := DEFAULT_GRID_SIZE
var cell_size := DEFAULT_CELL_SIZE


## 配置并初始化 `configure` 对应的模块状态。
## [param requested_grid_size] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_cell_size] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func configure(requested_grid_size: Vector2i, requested_cell_size := DEFAULT_CELL_SIZE) -> bool:
	if requested_grid_size.x <= 0 or requested_grid_size.y <= 0:
		push_error("Navigation grid dimensions must be positive")
		return false
	if requested_cell_size.x <= 0.0 or requested_cell_size.y <= 0.0:
		push_error("Navigation cell dimensions must be positive")
		return false
	grid_size = requested_grid_size
	cell_size = requested_cell_size
	return true


## 加载并校验 `load_from` 对应的模块状态。
## [param path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_grid_size] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_cell_size] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func load_from(
	path: String,
	requested_grid_size := Vector2i.ZERO,
	requested_cell_size := Vector2.ZERO,
) -> bool:
	if requested_grid_size != Vector2i.ZERO:
		var effective_cell_size := (
			requested_cell_size if requested_cell_size != Vector2.ZERO else DEFAULT_CELL_SIZE
		)
		if not configure(requested_grid_size, effective_cell_size):
			return false
	data = FileAccess.get_file_as_bytes(path)
	if data.size() != grid_size.x * grid_size.y:
		push_error(
			"Navigation grid has %d cells; expected %d × %d" % [
				data.size(), grid_size.x, grid_size.y,
			]
		)
		return false
	_build_graph()
	return true


## 查询并返回 `find_path` 对应的模块状态。
## [param from_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param to_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param should_simplify] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func find_path(
	from_position: Vector2,
	to_position: Vector2,
	should_simplify := true,
) -> PackedVector2Array:
	if not is_walkable(to_position):
		return PackedVector2Array()
	var from_id := cell_id(world_to_cell(from_position))
	var to_id := cell_id(world_to_cell(to_position))
	if not graph.has_point(from_id) or not graph.has_point(to_id):
		return PackedVector2Array()
	var astar_path := graph.get_point_path(from_id, to_id)
	if astar_path.is_empty():
		return PackedVector2Array()
	var raw_path := PackedVector2Array([from_position])
	for point in astar_path:
		if raw_path[-1].distance_squared_to(point) > 0.01:
			raw_path.append(point)
	if raw_path[-1].distance_squared_to(to_position) > 0.01:
		raw_path.append(to_position)
	else:
		raw_path[-1] = to_position
	return simplify_path(raw_path) if should_simplify else raw_path


## 执行 `closest_reachable_position` 对应的模块操作。
## [param from_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func closest_reachable_position(from_position: Vector2, requested_position: Vector2) -> Vector2:
	var from_id := cell_id(world_to_cell(from_position))
	if not graph.has_point(from_id):
		return Vector2.INF
	var closest_id := graph.get_closest_point(requested_position)
	if closest_id < 0:
		return Vector2.INF
	# The hall is normally one connected navigation component. Keep a complete
	# fallback for future maps that contain disconnected walkable islands.
	if not graph.get_id_path(from_id, closest_id).is_empty():
		return graph.get_point_position(closest_id)
	var best_position := Vector2.INF
	var best_distance_squared := INF
	var pending: Array[int] = [from_id]
	var visited := {from_id: true}
	var cursor := 0
	while cursor < pending.size():
		var point_id := pending[cursor]
		cursor += 1
		var candidate := graph.get_point_position(point_id)
		var distance_squared := candidate.distance_squared_to(requested_position)
		if distance_squared < best_distance_squared:
			best_position = candidate
			best_distance_squared = distance_squared
		for connected_id in graph.get_point_connections(point_id):
			if not visited.has(connected_id):
				visited[connected_id] = true
				pending.append(connected_id)
	return best_position


## 执行 `closest_walkable_position` 对应的模块操作。
## [param requested_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func closest_walkable_position(requested_position: Vector2) -> Vector2:
	var closest_id := graph.get_closest_point(requested_position)
	if closest_id < 0:
		return Vector2.INF
	return graph.get_point_position(closest_id)


## 执行 `simplify_path` 对应的模块操作。
## [param raw_path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func simplify_path(raw_path: PackedVector2Array) -> PackedVector2Array:
	if raw_path.size() <= 2:
		return raw_path
	var simplified := PackedVector2Array([raw_path[0]])
	var anchor := 0
	while anchor < raw_path.size() - 1:
		var next_index := raw_path.size() - 1
		while next_index > anchor + 1 and not segment_is_walkable(
			raw_path[anchor], raw_path[next_index]
		):
			next_index -= 1
		simplified.append(raw_path[next_index])
		anchor = next_index
	return simplified


## 执行 `segment_is_walkable` 对应的模块操作。
## [param from_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param to_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func segment_is_walkable(from_position: Vector2, to_position: Vector2) -> bool:
	var distance := from_position.distance_to(to_position)
	var sample_count := maxi(1, ceili(distance / LINE_OF_SIGHT_SAMPLE_STEP))
	for sample_index in range(sample_count + 1):
		var weight := float(sample_index) / float(sample_count)
		if not is_walkable(from_position.lerp(to_position, weight)):
			return false
	return true


## 执行 `world_to_cell` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func world_to_cell(world_position: Vector2) -> Vector2i:
	# Exact coordinate transform used by nEngineBkTile (enginebktile.cpp).
	var projected_y := (
		world_position.y * cell_size.x / (2.0 * cell_size.y) + cell_size.x * 0.5
	)
	var positive_diagonal := floori((projected_y + world_position.x) / cell_size.x)
	var negative_diagonal := floori((projected_y - world_position.x) / cell_size.x)
	return Vector2i(
		floori(float(positive_diagonal - negative_diagonal) / 2.0),
		positive_diagonal + negative_diagonal,
	)


## 执行 `cell_to_world` 对应的模块操作。
## [param cell] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		cell.x * cell_size.x + (cell_size.x * 0.5 if cell.y % 2 else 0.0),
		cell.y * cell_size.y,
	)


## 执行 `cell_id` 对应的模块操作。
## [param cell] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func cell_id(cell: Vector2i) -> int:
	return cell.y * grid_size.x + cell.x


## 执行 `raw_cell_walkable` 对应的模块操作。
## [param cell] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func raw_cell_walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= grid_size.x or cell.y < 0 or cell.y >= grid_size.y:
		return false
	var index := cell_id(cell)
	return index < data.size() and data[index] != 0


## 判断 `is_walkable` 对应的模块状态。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func is_walkable(world_position: Vector2) -> bool:
	return raw_cell_walkable(world_to_cell(world_position))


## 创建 `build_graph` 对应的模块状态。
## 设计：该函数遵循所在模块的职责边界。
func _build_graph() -> void:
	graph = AStar2D.new()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if raw_cell_walkable(cell):
				graph.add_point(cell_id(cell), cell_to_world(cell))

	# Four edge-neighbours of each navigation diamond.
	for y in range(grid_size.y - 1):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if not raw_cell_walkable(cell):
				continue
			var next_columns := [x - 1, x] if y % 2 == 0 else [x, x + 1]
			for next_x in next_columns:
				var next_cell := Vector2i(next_x, y + 1)
				if raw_cell_walkable(next_cell):
					_connect(cell, next_cell)

	# Four corner-neighbours complete eight-direction movement. Both cells
	# flanking a corner must be walkable, which prevents cutting through walls.
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if not raw_cell_walkable(cell):
				continue
			var shared_x := x if y % 2 == 0 else x + 1
			var east := Vector2i(x + 1, y)
			if (
				raw_cell_walkable(east)
				and raw_cell_walkable(Vector2i(shared_x, y - 1))
				and raw_cell_walkable(Vector2i(shared_x, y + 1))
			):
				_connect(cell, east)
			var south := Vector2i(x, y + 2)
			var lower_left := Vector2i(x - 1 if y % 2 == 0 else x, y + 1)
			var lower_right := Vector2i(x if y % 2 == 0 else x + 1, y + 1)
			if (
				raw_cell_walkable(south)
				and raw_cell_walkable(lower_left)
				and raw_cell_walkable(lower_right)
			):
				_connect(cell, south)


## 执行 `connect` 对应的模块操作。
## [param from_cell] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param to_cell] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数遵循所在模块的职责边界。
func _connect(from_cell: Vector2i, to_cell: Vector2i) -> void:
	var from_id := cell_id(from_cell)
	var to_id := cell_id(to_cell)
	if graph.has_point(from_id) and graph.has_point(to_id):
		graph.connect_points(from_id, to_id)
