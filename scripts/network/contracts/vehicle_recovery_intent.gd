class_name VehicleRecoveryIntent
extends RefCounted

const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const Result := preload("res://scripts/core/domain_result.gd")
const Validation := preload("res://scripts/network/contracts/contract_validation.gd")
const RETURN_TO_BASE := "return_to_base"
const ALLOWED_FIELDS: Array[StringName] = [
	&"map_instance_id",
	&"action",
	&"input_sequence",
]

var map_instance_id: String
var action: String
var input_sequence: int


## 创建只表达击毁后选择的恢复意图；客户端不能声明目的地图、坐标或恢复生命值。
## [param requested_map_instance_id] 调用方传入的 `requested_map_instance_id` 参数。
## [param requested_action] 调用方传入的 `requested_action` 参数。
## [param sequence] 调用方传入的 `sequence` 参数。
func _init(requested_map_instance_id: String, requested_action: String, sequence: int) -> void:
	map_instance_id = requested_map_instance_id
	action = requested_action
	input_sequence = sequence


## 使用网络边界的严格白名单校验当前实例。
func validate():
	var result = from_dictionary(to_dictionary())
	return Result.ok(self) if result.is_ok else result


## 序列化为稳定的三字段载荷。
## 返回该函数计算、查询或操作得到的结果。
func to_dictionary() -> Dictionary:
	return {
		"map_instance_id": map_instance_id,
		"action": action,
		"input_sequence": input_sequence,
	}


## 从不可信网络字典恢复击毁后恢复意图。
## [param raw] 调用方传入的 `raw` 参数。
static func from_dictionary(raw: Variant):
	var dictionary_result = Validation.require_dictionary(raw, "vehicle recovery intent")
	if not dictionary_result.is_ok:
		return dictionary_result
	var source: Dictionary = dictionary_result.value
	var fields_result = Validation.require_only_fields(
		source, ALLOWED_FIELDS, "vehicle recovery intent"
	)
	if not fields_result.is_ok:
		return fields_result
	var map_result = Validation.require_identifier(source, &"map_instance_id")
	if not map_result.is_ok:
		return map_result
	var action_result = Validation.require_identifier(source, &"action")
	if not action_result.is_ok:
		return action_result
	var sequence_result = Validation.require_integer(
		source, &"input_sequence", Protocol.MIN_SEQUENCE, Protocol.MAX_SEQUENCE
	)
	if not sequence_result.is_ok:
		return sequence_result
	return Result.ok(load(
		"res://scripts/network/contracts/vehicle_recovery_intent.gd"
	).new(map_result.value, action_result.value, sequence_result.value))
