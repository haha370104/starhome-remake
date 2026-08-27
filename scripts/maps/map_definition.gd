class_name MapDefinition
extends RefCounted

var schema_version := 1
var map_id: StringName
var display_name := ""
var legacy_codes: PackedStringArray = []
var category := "unknown"
var world_size := Vector2.ZERO
var navigation_grid_size := Vector2i.ZERO
var navigation_cell_size := Vector2.ZERO
var navigation_data_path := ""
var asset_ids: Dictionary = {}
var resource_paths: Dictionary = {}
var default_spawn_id: StringName
var spawn_points: Array[MapSpawnPoint] = []
var navigation_overrides: Array[Dictionary] = []
var player_presentation: Dictionary = {"kind": "character"}
var transitions: Array[MapTransition] = []
var source_audit: Dictionary = {}


## Retrieves the requested value from the managed state.
## [param transition_id] Stable identifier of the target value.
## Returns the resolved map model, or null when no match exists.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func transition_by_id(transition_id: StringName) -> MapTransition:
	for transition in transitions:
		if transition.transition_id == transition_id:
			return transition
	return null


## Performs the `enabled_transitions` operation.
## Returns the resulting collection.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func enabled_transitions() -> Array[MapTransition]:
	var result: Array[MapTransition] = []
	for transition in transitions:
		if transition.enabled:
			result.append(transition)
	return result


## 查找稳定业务标识为 [param spawn_id] 的出生点。
## Returns 匹配的出生点；不存在时返回 null。
func spawn_by_id(spawn_id: StringName) -> MapSpawnPoint:
	for spawn_point in spawn_points:
		if spawn_point.spawn_id == spawn_id:
			return spawn_point
	return null


## 查找普通旧传送入口号 [param entry_number] 对应的已启用出生点。
## Returns 精确入口匹配；入口未配置时返回默认出生点；两者都不存在时返回 null。
## Design: 旧客户端普通传送只携带入口号，不能把源图 approach_point 冒充目标落点。
func spawn_for_entry(entry_number: int) -> MapSpawnPoint:
	for spawn_point in spawn_points:
		if spawn_point.enabled and spawn_point.entry_number == entry_number:
			return spawn_point
	var fallback := spawn_by_id(default_spawn_id)
	return fallback if fallback != null and fallback.enabled else null
