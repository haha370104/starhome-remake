class_name MapJoined
extends RefCounted

const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")
const Validation = preload("res://scripts/network/contracts/contract_validation.gd")
const ALLOWED_FIELDS: Array[StringName] = [
	&"map_id",
	&"map_instance_id",
	&"entity_id",
	&"spawn_position",
	&"definition_version",
	&"server_tick",
]

var map_id: String
var map_instance_id: String
var entity_id: String
var spawn_position: Vector2
var definition_version: int
var server_tick: int


## 使用调用方参数初始化当前实例。
## [param requested_map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_spawn_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_definition_version] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func _init(
	requested_map_id: String,
	requested_map_instance_id: String,
	requested_entity_id: String,
	requested_spawn_position: Vector2,
	requested_definition_version: int,
	requested_server_tick: int,
) -> void:
	map_id = requested_map_id
	map_instance_id = requested_map_instance_id
	entity_id = requested_entity_id
	spawn_position = requested_spawn_position
	definition_version = requested_definition_version
	server_tick = requested_server_tick


## 校验 `validate` 对应的模块状态。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func validate():
	var result = from_dictionary(to_dictionary())
	return Result.ok(self) if result.is_ok else result


## 序列化或保存 `to_dictionary` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func to_dictionary() -> Dictionary:
	return {
		"map_id": map_id,
		"map_instance_id": map_instance_id,
		"entity_id": entity_id,
		"spawn_position": Validation.vector2_to_dictionary(spawn_position),
		"definition_version": definition_version,
		"server_tick": server_tick,
	}


## 加载并校验 `from_dictionary` 对应的模块状态。
## [param raw] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func from_dictionary(raw: Variant):
	var dictionary_result = Validation.require_dictionary(raw, "map joined")
	if not dictionary_result.is_ok:
		return dictionary_result
	var source: Dictionary = dictionary_result.value
	var fields_result = Validation.require_only_fields(source, ALLOWED_FIELDS, "map joined")
	if not fields_result.is_ok:
		return fields_result
	var map_result = Validation.require_identifier(source, &"map_id")
	if not map_result.is_ok:
		return map_result
	var instance_result = Validation.require_identifier(source, &"map_instance_id")
	if not instance_result.is_ok:
		return instance_result
	var entity_result = Validation.require_identifier(source, &"entity_id")
	if not entity_result.is_ok:
		return entity_result
	var spawn_result = Validation.require_vector2(source, &"spawn_position")
	if not spawn_result.is_ok:
		return spawn_result
	var version_result = Validation.require_integer(source, &"definition_version", 1, Protocol.MAX_SEQUENCE)
	if not version_result.is_ok:
		return version_result
	var tick_result = Validation.require_integer(source, &"server_tick", 0, Protocol.MAX_SERVER_TICK)
	if not tick_result.is_ok:
		return tick_result
	return Result.ok(load("res://scripts/network/contracts/map_joined.gd").new(
		map_result.value,
		instance_result.value,
		entity_result.value,
		spawn_result.value,
		version_result.value,
		tick_result.value,
	))
