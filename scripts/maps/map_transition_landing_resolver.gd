class_name MapTransitionLandingResolver
extends RefCounted

const EDGE_THRESHOLD := 0.12
const ENTRY_MISMATCH_PENALTY := 4.0


## 根据目标地图指回来源地图的反向出口，计算保持地图空间连续性的权威落点。
## [param source_definition] 玩家离开的地图定义。
## [param source_transition] 玩家触发的来源出口。
## [param destination_definition] 权威服务器解析出的目标地图定义。
## 返回包含落点、证据类型和反向出口 ID 的结果；不存在反向边时回退到入口号出生点。
static func resolve_landing(
	source_definition: MapDefinition,
	source_transition: MapTransition,
	destination_definition: MapDefinition,
) -> Dictionary:
	if source_definition == null or source_transition == null or destination_definition == null:
		return {}
	var reciprocal_candidates: Array[MapTransition] = []
	if source_definition != destination_definition:
		for candidate: MapTransition in destination_definition.enabled_transitions():
			if _targets_source_map(candidate, source_definition):
				reciprocal_candidates.append(candidate)
	if not reciprocal_candidates.is_empty():
		var expected_position := _continuous_target_position(
			source_transition.approach_point,
			source_definition.world_size,
			destination_definition.world_size,
		)
		var best: MapTransition
		var best_score := INF
		for candidate: MapTransition in reciprocal_candidates:
			var score := _normalized_distance_squared(
				candidate.approach_point,
				expected_position,
				destination_definition.world_size,
			)
			if candidate.destination_entry_number != source_transition.destination_entry_number:
				score += ENTRY_MISMATCH_PENALTY
			if (
				best == null
				or score < best_score
				or (
					is_equal_approx(score, best_score)
					and String(candidate.transition_id) < String(best.transition_id)
				)
			):
				best = candidate
				best_score = score
		if best != null:
			return {
				"position": best.approach_point,
				"evidence": "reciprocal_exit",
				"reciprocal_transition_id": best.transition_id,
			}
	if (
		source_definition != destination_definition
		and source_definition.category == "field"
		and destination_definition.category == "field"
	):
		return {
			"position": _continuous_target_position(
				source_transition.approach_point,
				source_definition.world_size,
				destination_definition.world_size,
			),
			"evidence": "wrapped_field_edge",
		}
	var fallback: MapSpawnPoint = destination_definition.spawn_for_entry(
		source_transition.destination_entry_number
	)
	if fallback == null:
		return {}
	return {
		"position": fallback.position,
		"evidence": "entry_spawn_fallback",
		"spawn_id": fallback.spawn_id,
	}


## 判断目标图出口是否明确或通过同世界旧代码指回来源地图。
## [param transition] 目标地图上的候选反向出口。
## [param source_definition] 候选出口应当指向的来源地图。
## 返回候选出口是否构成来源边的反向关系。
static func _targets_source_map(
	transition: MapTransition,
	source_definition: MapDefinition,
) -> bool:
	if transition.destination_map_id == source_definition.map_id:
		return true
	if transition.destination_legacy_code.is_empty():
		return false
	if (
		not transition.destination_world_id.is_empty()
		and transition.destination_world_id != source_definition.world_id
	):
		return false
	return transition.destination_legacy_code.to_lower() in source_definition.legacy_codes


## 将来源出口的边缘位置映射到目标地图相对的边缘，并保留另一轴的连续比例。
## [param source_position] 来源地图中玩家到达的出口接近点。
## [param source_size] 来源地图世界尺寸。
## [param destination_size] 目标地图世界尺寸。
## 返回用于多个反向出口消歧的目标地图期望位置。
static func _continuous_target_position(
	source_position: Vector2,
	source_size: Vector2,
	destination_size: Vector2,
) -> Vector2:
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return destination_size * 0.5
	var normalized := Vector2(
		clampf(source_position.x / source_size.x, 0.0, 1.0),
		clampf(source_position.y / source_size.y, 0.0, 1.0),
	)
	var near_x_edge := minf(normalized.x, 1.0 - normalized.x) <= EDGE_THRESHOLD
	var near_y_edge := minf(normalized.y, 1.0 - normalized.y) <= EDGE_THRESHOLD
	if near_x_edge:
		normalized.x = 1.0 - normalized.x
	if near_y_edge:
		normalized.y = 1.0 - normalized.y
	if not near_x_edge and not near_y_edge:
		var horizontal_distance := minf(normalized.x, 1.0 - normalized.x)
		var vertical_distance := minf(normalized.y, 1.0 - normalized.y)
		if horizontal_distance <= vertical_distance:
			normalized.x = 1.0 - normalized.x
		else:
			normalized.y = 1.0 - normalized.y
	return normalized * destination_size


## 计算目标地图中的两个位置经过尺寸归一化后的平方距离。
## [param first] 第一个目标地图位置。
## [param second] 第二个目标地图位置。
## [param world_size] 目标地图世界尺寸。
## 返回不受不同地图像素尺寸影响的平方距离。
static func _normalized_distance_squared(
	first: Vector2,
	second: Vector2,
	world_size: Vector2,
) -> float:
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		return first.distance_squared_to(second)
	return Vector2(first.x / world_size.x, first.y / world_size.y).distance_squared_to(
		Vector2(second.x / world_size.x, second.y / world_size.y)
	)
