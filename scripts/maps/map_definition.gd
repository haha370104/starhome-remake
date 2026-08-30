class_name MapDefinition
extends RefCounted

var schema_version := 1
var map_id: StringName
var world_id: StringName = &"legacy_world"
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


## 执行 `transition_by_id` 对应的模块操作。
## [param transition_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func transition_by_id(transition_id: StringName) -> MapTransition:
	for transition in transitions:
		if transition.transition_id == transition_id:
			return transition
	return null


## 执行 `enabled_transitions` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func enabled_transitions() -> Array[MapTransition]:
	var result: Array[MapTransition] = []
	for transition in transitions:
		if transition.enabled:
			result.append(transition)
	return result


## 执行 `spawn_by_id` 对应的模块操作。
## [param spawn_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func spawn_by_id(spawn_id: StringName) -> MapSpawnPoint:
	for spawn_point in spawn_points:
		if spawn_point.spawn_id == spawn_id:
			return spawn_point
	return null


## 执行 `spawn_for_entry` 对应的模块操作。
## [param entry_number] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：旧客户端普通传送只携带入口号，不能把源图 approach_point 冒充目标落点。
func spawn_for_entry(entry_number: int) -> MapSpawnPoint:
	for spawn_point in spawn_points:
		if spawn_point.enabled and spawn_point.entry_number == entry_number:
			return spawn_point
	var fallback := spawn_by_id(default_spawn_id)
	return fallback if fallback != null and fallback.enabled else null
