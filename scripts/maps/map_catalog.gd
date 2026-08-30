class_name MapCatalog
extends RefCounted

var _by_id: Dictionary = {}
var _by_legacy_code_by_world: Dictionary = {}
var errors: PackedStringArray = []


## 执行 `clear` 对应的模块操作。
## 设计：该函数遵循所在模块的职责边界。
func clear() -> void:
	_by_id.clear()
	_by_legacy_code_by_world.clear()
	errors.clear()


## 执行 `add_map` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func add_map(definition: MapDefinition) -> bool:
	var succeeded := true
	var id_key := String(definition.map_id)
	if _by_id.has(id_key):
		_add_error("duplicate_map_id", "地图 ID 重复：%s" % id_key)
		succeeded = false
	for code in definition.legacy_codes:
		var normalized := code.to_lower()
		var world_index: Dictionary = _by_legacy_code_by_world.get(definition.world_id, {})
		if world_index.has(normalized):
			_add_error("duplicate_legacy_code", "旧地图代码重复：%s" % normalized)
			succeeded = false
	if not succeeded:
		return false
	_by_id[id_key] = definition
	if not _by_legacy_code_by_world.has(definition.world_id):
		_by_legacy_code_by_world[definition.world_id] = {}
	for code in definition.legacy_codes:
		(_by_legacy_code_by_world[definition.world_id] as Dictionary)[code.to_lower()] = definition
	return true


## 执行 `add_files` 对应的模块操作。
## [param paths] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func add_files(paths: PackedStringArray) -> bool:
	var LoaderScript := load("res://scripts/maps/map_definition_loader.gd")
	var succeeded := true
	for path in paths:
		var loader: MapDefinitionLoader = LoaderScript.new()
		var definition := loader.load_file(path)
		if definition == null:
			for issue in loader.errors:
				_add_error("load", "%s — %s" % [path, issue])
			succeeded = false
		elif not add_map(definition):
			succeeded = false
	return succeeded


## 执行 `map_by_id` 对应的模块操作。
## [param map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func map_by_id(map_id: StringName) -> MapDefinition:
	return _by_id.get(String(map_id))


## 执行 `map_by_legacy_code` 对应的模块操作。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func map_by_legacy_code(code: String, world_id: StringName = &"") -> MapDefinition:
	var normalized := code.strip_edges().to_lower()
	if not world_id.is_empty():
		return (_by_legacy_code_by_world.get(world_id, {}) as Dictionary).get(normalized)
	var unique_match: MapDefinition
	for world_index_value: Variant in _by_legacy_code_by_world.values():
		var candidate: MapDefinition = (world_index_value as Dictionary).get(normalized)
		if candidate == null:
			continue
		if unique_match != null and unique_match != candidate:
			return null
		unique_match = candidate
	return unique_match


## 执行 `source_audit_for_map` 对应的模块操作。
## [param map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func source_audit_for_map(map_id: StringName) -> Dictionary:
	var definition := map_by_id(map_id)
	return definition.source_audit.duplicate(true) if definition != null else {}


## 查询并返回 `resolve_target` 对应的模块状态。
## [param transition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func resolve_target(
	transition: MapTransition,
	source_world_id: StringName = &"legacy_world",
) -> MapDefinition:
	if not transition.destination_map_id.is_empty():
		var by_id := map_by_id(transition.destination_map_id)
		if by_id != null:
			return by_id
	if not transition.destination_legacy_code.is_empty():
		var target_world := transition.destination_world_id
		if target_world.is_empty():
			target_world = source_world_id
		return map_by_legacy_code(transition.destination_legacy_code, target_world)
	return null


## 校验 `validate_links` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func validate_links() -> bool:
	var succeeded := true
	for definition: MapDefinition in _by_id.values():
		for transition in definition.transitions:
			if not transition.enabled:
				continue
			if resolve_target(transition, definition.world_id) == null \
					and not transition.external_target:
				_add_error(
					"unresolved_target",
					"%s/%s 无法解析目标 %s" % [
						definition.map_id,
						transition.transition_id,
						transition.destination_key(),
					],
				)
				succeeded = false
	return succeeded


## 执行 `all_maps` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func all_maps() -> Array[MapDefinition]:
	var result: Array[MapDefinition] = []
	for definition: MapDefinition in _by_id.values():
		result.append(definition)
	result.sort_custom(
		func(a: MapDefinition, b: MapDefinition) -> bool: return String(a.map_id) < String(b.map_id)
	)
	return result


## 执行 `unresolved_external_transitions` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func unresolved_external_transitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: MapDefinition in _by_id.values():
		for transition in definition.transitions:
			if transition.enabled and transition.external_target \
					and resolve_target(transition, definition.world_id) == null:
				result.append({
					"source_map_id": definition.map_id,
					"transition_id": transition.transition_id,
					"destination_key": transition.destination_key(),
					"source_audit": transition.source_audit.duplicate(true),
				})
	return result


## 执行 `size` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func size() -> int:
	return _by_id.size()


## 执行 `add_error` 对应的模块操作。
## [param kind] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数遵循所在模块的职责边界。
func _add_error(kind: String, message: String) -> void:
	errors.append("%s: %s" % [kind, message])
