class_name RuntimeMapRouteResolver
extends RefCounted

const DEFAULT_INDEX_PATH := "res://data/content/glory_map_runtime_index_v1.json"

var errors: PackedStringArray = []
var _definition_paths: Dictionary = {}
var _map_ids_by_legacy_world: Dictionary = {}


## 从受控客户端目录和荣耀版运行索引建立旧地图代码到运行时地图 ID 的映射。
## [param definition_paths] 受控地图 ID 到本地定义路径的映射。
## [param index_path] 荣耀版运行地图索引路径。
## 返回索引是否完整且不存在世界内旧代码冲突。
func configure(definition_paths: Dictionary, index_path := DEFAULT_INDEX_PATH) -> bool:
	errors.clear()
	_definition_paths.clear()
	_map_ids_by_legacy_world.clear()
	for map_id_value: Variant in definition_paths:
		var map_id := StringName(String(map_id_value))
		var definition_path := String(definition_paths[map_id_value])
		if not map_id.is_empty() and definition_path.begins_with("res://"):
			_definition_paths[map_id] = definition_path
	if not FileAccess.file_exists(index_path):
		errors.append("运行地图索引不存在：%s" % index_path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	if not parsed is Dictionary or not parsed.get("runtime_maps", []) is Array:
		errors.append("运行地图索引格式无效：%s" % index_path)
		return false
	for row_value: Variant in parsed["runtime_maps"]:
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value
		var map_id := StringName(String(row.get("runtime_id", "")))
		var world_id := StringName(String(row.get("world_id", "")))
		var legacy_code := String(row.get("map_code", "")).strip_edges().to_lower()
		if map_id.is_empty() or world_id.is_empty() or legacy_code.is_empty():
			continue
		if not _definition_paths.has(map_id):
			continue
		if not _map_ids_by_legacy_world.has(world_id):
			_map_ids_by_legacy_world[world_id] = {}
		var world_index: Dictionary = _map_ids_by_legacy_world[world_id]
		if world_index.has(legacy_code) and world_index[legacy_code] != map_id:
			errors.append("地图旧代码重复：%s/%s" % [world_id, legacy_code])
			continue
		world_index[legacy_code] = map_id
	return errors.is_empty()


## 将地图定义中的内部 ID 或旧版世界/地图代码解析成受控目录内的运行时地图 ID。
## [param transition] 当前地图定义提供的出口。
## [param source_world_id] 未显式声明目标世界时使用的当前世界 ID。
## 返回受控目录内的目标地图 ID；无法可靠解析时返回空值。
func resolve_target_id(transition: MapTransition, source_world_id: StringName) -> StringName:
	if transition == null:
		return &""
	if (
		not transition.destination_map_id.is_empty()
		and _definition_paths.has(transition.destination_map_id)
	):
		return transition.destination_map_id
	if transition.destination_legacy_code.is_empty():
		return &""
	var target_world_id := transition.destination_world_id
	if target_world_id.is_empty():
		target_world_id = source_world_id
	var world_index: Dictionary = _map_ids_by_legacy_world.get(target_world_id, {})
	return StringName(String(world_index.get(
		transition.destination_legacy_code.strip_edges().to_lower(),
		"",
	)))


## 查询当前允许客户端预载的地图定义数量。
## 返回已登记的运行地图总数。
func size() -> int:
	return _definition_paths.size()
