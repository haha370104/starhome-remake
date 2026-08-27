class_name MapCatalog
extends RefCounted

var _by_id: Dictionary = {}
var _by_legacy_code: Dictionary = {}
var errors: PackedStringArray = []


## Resets the managed state to its initial value.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func clear() -> void:
	_by_id.clear()
	_by_legacy_code.clear()
	errors.clear()


## Mutates the managed collection for the requested value.
## [param definition] Configuration data that controls the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func add_map(definition: MapDefinition) -> bool:
	var succeeded := true
	var id_key := String(definition.map_id)
	if _by_id.has(id_key):
		_add_error("duplicate_map_id", "地图 ID 重复：%s" % id_key)
		succeeded = false
	for code in definition.legacy_codes:
		var normalized := code.to_lower()
		if _by_legacy_code.has(normalized):
			_add_error("duplicate_legacy_code", "旧地图代码重复：%s" % normalized)
			succeeded = false
	if not succeeded:
		return false
	_by_id[id_key] = definition
	for code in definition.legacy_codes:
		_by_legacy_code[code.to_lower()] = definition
	return true


## Mutates the managed collection for the requested value.
## [param paths] Resource or movement path consumed by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
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


## Retrieves the requested value from the managed state.
## [param map_id] Stable identifier of the target value.
## Returns the resolved map model, or null when no match exists.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func map_by_id(map_id: StringName) -> MapDefinition:
	return _by_id.get(String(map_id))


## Performs the `map_by_legacy_code` operation.
## [param code] Stable identifier of the target value.
## Returns the resolved map model, or null when no match exists.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func map_by_legacy_code(code: String) -> MapDefinition:
	return _by_legacy_code.get(code.strip_edges().to_lower())


## Retrieves the requested value from the managed state.
## [param map_id] Stable identifier of the target value.
## Returns Structured result data produced by the operation.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func source_audit_for_map(map_id: StringName) -> Dictionary:
	var definition := map_by_id(map_id)
	return definition.source_audit.duplicate(true) if definition != null else {}


## Resolves the best matching value for the supplied query.
## [param transition] Input value consumed by the operation.
## Returns the resolved map model, or null when no match exists.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func resolve_target(transition: MapTransition) -> MapDefinition:
	if not transition.destination_map_id.is_empty():
		var by_id := map_by_id(transition.destination_map_id)
		if by_id != null:
			return by_id
	if not transition.destination_legacy_code.is_empty():
		return map_by_legacy_code(transition.destination_legacy_code)
	return null


## Validates the supplied state against the domain invariants.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func validate_links() -> bool:
	var succeeded := true
	for definition: MapDefinition in _by_id.values():
		for transition in definition.transitions:
			if not transition.enabled:
				continue
			if resolve_target(transition) == null and not transition.external_target:
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


## Performs the `all_maps` operation.
## Returns the resulting collection.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func all_maps() -> Array[MapDefinition]:
	var result: Array[MapDefinition] = []
	for definition: MapDefinition in _by_id.values():
		result.append(definition)
	result.sort_custom(
		func(a: MapDefinition, b: MapDefinition) -> bool: return String(a.map_id) < String(b.map_id)
	)
	return result


## Performs the `unresolved_external_transitions` operation.
## Returns the resulting collection.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func unresolved_external_transitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: MapDefinition in _by_id.values():
		for transition in definition.transitions:
			if transition.enabled and transition.external_target and resolve_target(transition) == null:
				result.append({
					"source_map_id": definition.map_id,
					"transition_id": transition.transition_id,
					"destination_key": transition.destination_key(),
					"source_audit": transition.source_audit.duplicate(true),
				})
	return result


## Performs the `size` operation.
## Returns the computed integer value.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func size() -> int:
	return _by_id.size()


## Mutates the managed collection for the requested value.
## [param kind] Stable identifier of the target value.
## [param message] Serialized input received at the subsystem boundary.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func _add_error(kind: String, message: String) -> void:
	errors.append("%s: %s" % [kind, message])
