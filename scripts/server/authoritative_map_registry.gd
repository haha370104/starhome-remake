class_name AuthoritativeMapRegistry
extends RefCounted

const ErrorCodes := preload("res://scripts/network/contracts/network_error_codes.gd")

var _by_instance_id: Dictionary = {}
var _by_map_id: Dictionary = {}
var _by_legacy_code: Dictionary = {}


## 执行 `register_instance` 对应的模块操作。
## [param instance] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
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


## 执行 `instance_by_id` 对应的模块操作。
## [param instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func instance_by_id(instance_id: String) -> AuthoritativeMapInstance:
	return _by_instance_id.get(instance_id)


## 按业务地图标识查询当前服务器登记的运行实例。
## [param map_id] 不含运行实例后缀的稳定业务地图标识。
## 返回该函数计算、查询或操作得到的结果。
func instance_by_map_id(map_id: String) -> AuthoritativeMapInstance:
	return _by_map_id.get(map_id)


## 执行 `resolve_transition_target` 对应的模块操作。
## [param transition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func resolve_transition_target(transition: MapTransition) -> AuthoritativeMapInstance:
	if not transition.destination_map_id.is_empty():
		var by_id: AuthoritativeMapInstance = _by_map_id.get(String(transition.destination_map_id))
		if by_id != null:
			return by_id
	if not transition.destination_legacy_code.is_empty():
		return _by_legacy_code.get(transition.destination_legacy_code.strip_edges().to_lower())
	return null


## 执行 `all_instances` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func all_instances() -> Array[AuthoritativeMapInstance]:
	var keys := _by_instance_id.keys()
	keys.sort()
	var result: Array[AuthoritativeMapInstance] = []
	for key: String in keys:
		result.append(_by_instance_id[key])
	return result


## 执行 `success` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _success(value: Variant) -> Dictionary:
	return {"ok": true, "code": &"ok", "value": value}


## 执行 `failure` 对应的模块操作。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
