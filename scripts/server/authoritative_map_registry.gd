class_name AuthoritativeMapRegistry
extends RefCounted

const ErrorCodes := preload("res://scripts/network/contracts/network_error_codes.gd")

var _by_instance_id: Dictionary = {}
var _by_map_id: Dictionary = {}
var _by_legacy_code: Dictionary = {}


## Registers one fully loaded authoritative [param instance] under its business and legacy identifiers.
## [param instance] Loaded map instance whose definition and navigation are ready for simulation.
## Returns a success result containing the instance, or a duplicate/invalid identifier failure.
## Design: Registration is the admission boundary; unresolved map files never become transition targets.
func register_instance(instance: AuthoritativeMapInstance) -> Dictionary:
	if instance == null or instance.definition == null or instance.navigation == null:
		return _failure(&"map_registry.invalid_instance", "map instance is not fully loaded")
	var instance_key := String(instance.instance_id)
	var map_key := String(instance.definition.map_id)
	if instance_key.is_empty() or map_key.is_empty():
		return _failure(ErrorCodes.INVALID_IDENTIFIER, "map and instance identifiers are required")
	if _by_instance_id.has(instance_key) or _by_map_id.has(map_key):
		return _failure(&"map_registry.duplicate_map", "map or instance identifier is already registered")
	for legacy_code: String in instance.definition.legacy_codes:
		var normalized := legacy_code.strip_edges().to_lower()
		if not normalized.is_empty() and _by_legacy_code.has(normalized):
			return _failure(&"map_registry.duplicate_legacy_code", "legacy map code is already registered")
	_by_instance_id[instance_key] = instance
	_by_map_id[map_key] = instance
	for legacy_code: String in instance.definition.legacy_codes:
		var normalized := legacy_code.strip_edges().to_lower()
		if not normalized.is_empty():
			_by_legacy_code[normalized] = instance
	return _success(instance)


## Retrieves the authoritative instance identified by [param instance_id].
## [param instance_id] Stable map-instance identifier carried by commands and sessions.
## Returns the registered instance, or `null` when it is unknown.
func instance_by_id(instance_id: String) -> AuthoritativeMapInstance:
	return _by_instance_id.get(instance_id)


## Resolves the server-admitted target for [param transition].
## [param transition] Source-map transition containing a business map ID and/or legacy code.
## Returns the registered target instance, or `null` for missing and external-only targets.
## Design: Runtime transfer resolution never reads arbitrary paths supplied by a client.
func resolve_transition_target(transition: MapTransition) -> AuthoritativeMapInstance:
	if not transition.destination_map_id.is_empty():
		var by_id: AuthoritativeMapInstance = _by_map_id.get(String(transition.destination_map_id))
		if by_id != null:
			return by_id
	if not transition.destination_legacy_code.is_empty():
		return _by_legacy_code.get(transition.destination_legacy_code.strip_edges().to_lower())
	return null


## Retrieves every registered instance in deterministic instance-ID order.
## Returns a typed array used by fixed-step simulation and snapshot publication.
func all_instances() -> Array[AuthoritativeMapInstance]:
	var keys := _by_instance_id.keys()
	keys.sort()
	var result: Array[AuthoritativeMapInstance] = []
	for key: String in keys:
		result.append(_by_instance_id[key])
	return result


## Builds a conventional successful server operation result for [param value].
## [param value] Value returned to the registry caller.
## Returns a dictionary with stable `ok`, `code`, and `value` fields.
func _success(value: Variant) -> Dictionary:
	return {"ok": true, "code": &"ok", "value": value}


## Builds a conventional failed server operation result.
## [param code] Stable machine-readable failure code.
## [param message] Human-readable diagnostic message.
## Returns a dictionary with stable `ok`, `code`, and `message` fields.
func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
