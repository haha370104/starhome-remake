class_name MoveIntent
extends RefCounted

const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")
const Validation = preload("res://scripts/network/contracts/contract_validation.gd")
const ALLOWED_FIELDS: Array[StringName] = [
	&"map_instance_id",
	&"requested_world_point",
	&"input_sequence",
]

var map_instance_id: String
var requested_world_point: Vector2
var input_sequence: int


## 使用调用方参数初始化当前实例。
## [param requested_map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param world_point] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_input_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func _init(requested_map_instance_id: String, world_point: Vector2, requested_input_sequence: int) -> void:
	map_instance_id = requested_map_instance_id
	requested_world_point = world_point
	input_sequence = requested_input_sequence


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
		"map_instance_id": map_instance_id,
		"requested_world_point": Validation.vector2_to_dictionary(requested_world_point),
		"input_sequence": input_sequence,
	}


## 加载并校验 `from_dictionary` 对应的模块状态。
## [param raw] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func from_dictionary(raw: Variant):
	var dictionary_result = Validation.require_dictionary(raw, "move intent")
	if not dictionary_result.is_ok:
		return dictionary_result
	var source: Dictionary = dictionary_result.value
	var fields_result = Validation.require_only_fields(source, ALLOWED_FIELDS, "move intent")
	if not fields_result.is_ok:
		return fields_result
	var map_result = Validation.require_identifier(source, &"map_instance_id")
	if not map_result.is_ok:
		return map_result
	var point_result = Validation.require_vector2(source, &"requested_world_point")
	if not point_result.is_ok:
		return point_result
	var sequence_result = Validation.require_integer(
		source,
		&"input_sequence",
		Protocol.MIN_SEQUENCE,
		Protocol.MAX_SEQUENCE,
	)
	if not sequence_result.is_ok:
		return sequence_result
	return Result.ok(load("res://scripts/network/contracts/move_intent.gd").new(
		map_result.value,
		point_result.value,
		sequence_result.value,
	))
