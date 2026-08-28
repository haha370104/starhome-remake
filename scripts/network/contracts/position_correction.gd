class_name PositionCorrection
extends RefCounted

const ErrorCodes = preload("res://scripts/network/contracts/network_error_codes.gd")
const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")
const Validation = preload("res://scripts/network/contracts/contract_validation.gd")

const REASON_NAVIGATION: StringName = &"navigation"
const REASON_SPEED_LIMIT: StringName = &"speed_limit"
const REASON_MAP_STATE: StringName = &"map_state"
const REASON_SERVER_RECONCILIATION: StringName = &"server_reconciliation"

var authoritative_position: Vector2
var reason: StringName
var acknowledged_input_sequence: int
var server_tick: int


## 使用调用方参数初始化当前实例。
## [param requested_authoritative_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_reason] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_acknowledged_input_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func _init(
	requested_authoritative_position: Vector2,
	requested_reason: StringName,
	requested_acknowledged_input_sequence: int,
	requested_server_tick: int,
) -> void:
	authoritative_position = requested_authoritative_position
	reason = requested_reason
	acknowledged_input_sequence = requested_acknowledged_input_sequence
	server_tick = requested_server_tick


## 执行 `supported_reasons` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func supported_reasons() -> Array[StringName]:
	return [REASON_NAVIGATION, REASON_SPEED_LIMIT, REASON_MAP_STATE, REASON_SERVER_RECONCILIATION]


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
		"authoritative_position": Validation.vector2_to_dictionary(authoritative_position),
		"reason": String(reason),
		"acknowledged_input_sequence": acknowledged_input_sequence,
		"server_tick": server_tick,
	}


## 加载并校验 `from_dictionary` 对应的模块状态。
## [param raw] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func from_dictionary(raw: Variant):
	var dictionary_result = Validation.require_dictionary(raw, "position correction")
	if not dictionary_result.is_ok:
		return dictionary_result
	var source: Dictionary = dictionary_result.value
	var position_result = Validation.require_vector2(source, &"authoritative_position")
	if not position_result.is_ok:
		return position_result
	var reason_result = Validation.require_string(source, &"reason", 1, Protocol.MAX_ACTION_LENGTH)
	if not reason_result.is_ok:
		return reason_result
	var parsed_reason := StringName(reason_result.value)
	if parsed_reason not in supported_reasons():
		return Result.failure(ErrorCodes.VALUE_OUT_OF_RANGE, "Unsupported correction reason")
	var sequence_result = Validation.require_integer(
		source,
		&"acknowledged_input_sequence",
		Protocol.MIN_SEQUENCE,
		Protocol.MAX_SEQUENCE,
	)
	if not sequence_result.is_ok:
		return sequence_result
	var tick_result = Validation.require_integer(source, &"server_tick", 0, Protocol.MAX_SERVER_TICK)
	if not tick_result.is_ok:
		return tick_result
	return Result.ok(load("res://scripts/network/contracts/position_correction.gd").new(
		position_result.value,
		parsed_reason,
		sequence_result.value,
		tick_result.value,
	))
