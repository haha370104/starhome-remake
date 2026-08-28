class_name NetworkProtocol
extends RefCounted

const ErrorCodes = preload("res://scripts/network/contracts/network_error_codes.gd")
const Result = preload("res://scripts/core/domain_result.gd")

const PROTOCOL_VERSION := 1
const PUBLIC_CONTENT_VERSION := 1
const MIN_SEQUENCE := 0
const MAX_SEQUENCE := 2147483647
const MAX_SERVER_TICK := 9223372036854775807
const MAX_WORLD_COORDINATE := 10000000.0
const MAX_SPEED := 10000.0
const MAX_IDENTIFIER_LENGTH := 128
const MAX_ACTION_LENGTH := 64

const MOVE_INTENT: StringName = &"move_intent"
const MAP_TRANSITION_INTENT: StringName = &"map_transition_intent"
const USE_ABILITY_INTENT: StringName = &"use_ability_intent"
const ENTITY_SNAPSHOT: StringName = &"entity_snapshot"
const MAP_JOINED: StringName = &"map_joined"
const POSITION_CORRECTION: StringName = &"position_correction"


## 执行 `supported_message_types` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func supported_message_types() -> Array[StringName]:
	return [
		MOVE_INTENT,
		MAP_TRANSITION_INTENT,
		USE_ABILITY_INTENT,
		ENTITY_SNAPSHOT,
		MAP_JOINED,
		POSITION_CORRECTION,
	]


## 校验 `validate_versions` 对应的模块状态。
## [param protocol_version] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param content_version] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func validate_versions(protocol_version: int, content_version: int):
	if protocol_version != PROTOCOL_VERSION:
		return Result.failure(
			ErrorCodes.UNSUPPORTED_PROTOCOL_VERSION,
			"Unsupported protocol version: %d" % protocol_version,
		)
	if content_version != PUBLIC_CONTENT_VERSION:
		return Result.failure(
			ErrorCodes.CONTENT_VERSION_MISMATCH,
			"Public content version does not match: %d" % content_version,
		)
	return Result.ok()


## 判断 `is_supported_message_type` 对应的模块状态。
## [param message_type] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func is_supported_message_type(message_type: StringName) -> bool:
	return message_type in supported_message_types()
