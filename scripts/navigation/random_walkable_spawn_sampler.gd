class_name RandomWalkableSpawnSampler
extends RefCounted

const RANDOM_ATTEMPTS := 256


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
