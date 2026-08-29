class_name RandomWalkableSpawnSampler
extends RefCounted

const RANDOM_ATTEMPTS := 256


## 从导航图中确定性采样一个满足占用间距的随机可行走出生点。
## [param navigation] 提供图节点和坐标查询的地图导航对象。
## [param random_seed] 保证服务器重放一致性的随机种子。
## [param occupied_positions] 已被实体占用的世界坐标。
## [param minimum_separation] 新出生点与现有实体的最小距离。
## 返回满足条件的坐标；无候选点时返回无穷坐标。
static func sample(
	navigation,
	random_seed: int,
	occupied_positions: Array[Vector2],
	minimum_separation: float,
) -> Vector2:
	if navigation == null or navigation.graph == null:
		return Vector2.INF
	var point_ids: PackedInt64Array = navigation.graph.get_point_ids()
	if point_ids.is_empty():
		return Vector2.INF
	var random := RandomNumberGenerator.new()
	random.seed = random_seed
	var best_position := Vector2.INF
	var best_clearance_squared := -1.0
	var required_squared := maxf(0.0, minimum_separation) ** 2
	var attempts := mini(RANDOM_ATTEMPTS, point_ids.size())
	for _attempt in range(attempts):
		var point_id: int = point_ids[random.randi_range(0, point_ids.size() - 1)]
		var candidate: Vector2 = navigation.graph.get_point_position(point_id)
		var clearance_squared := _nearest_clearance_squared(candidate, occupied_positions)
		if clearance_squared >= required_squared:
			return candidate
		if clearance_squared > best_clearance_squared:
			best_clearance_squared = clearance_squared
			best_position = candidate
	return best_position


## 计算候选点与现有占用点之间最近距离的平方。
## [param candidate] 待评估的候选坐标。
## [param occupied_positions] 当前已占用的坐标集合。
## 返回最近距离平方；没有占用点时返回无穷大。
static func _nearest_clearance_squared(
	candidate: Vector2,
	occupied_positions: Array[Vector2],
) -> float:
	if occupied_positions.is_empty():
		return INF
	var nearest := INF
	for occupied: Vector2 in occupied_positions:
		nearest = minf(nearest, candidate.distance_squared_to(occupied))
	return nearest
