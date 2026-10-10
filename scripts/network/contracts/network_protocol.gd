class_name NetworkProtocol
extends RefCounted

const ErrorCodes = preload("res://scripts/network/contracts/network_error_codes.gd")
const Result = preload("res://scripts/core/domain_result.gd")

const PROTOCOL_VERSION := 5
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
const PICKUP_LOOT_INTENT: StringName = &"pickup_loot_intent"
const VEHICLE_RECOVERY_INTENT: StringName = &"vehicle_recovery_intent"
const SOCIAL_COMMAND: StringName = &"social_command"
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
		PICKUP_LOOT_INTENT,
		VEHICLE_RECOVERY_INTENT,
		SOCIAL_COMMAND,
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


## 隔离尚可变的世界快照；已经封存的快照可在传输与表现订阅者之间直接共享。
## [param snapshot] 只含协议值的快照，read-only 状态由 freeze_snapshot 递归建立。
## 返回不会随调用方后续修改而变化的只读快照；不替代字段校验。
static func share_snapshot(snapshot: Dictionary) -> Dictionary:
	if snapshot.is_read_only(): return snapshot
	var isolated := snapshot.duplicate(true)
	freeze_snapshot(isolated)
	return isolated


## 递归封存新构造的协议容器，发布后不再允许任何订阅者修改。
## [param value] 调用方独占的快照；不能传入仍被领域对象持有的可变容器。
## 设计：权威发布端转交快照所有权，接收端经 share_snapshot 隔离外部输入。
static func freeze_snapshot(value: Variant) -> void:
	if value is Dictionary:
		if value.is_read_only(): return
		for child: Variant in value.values(): freeze_snapshot(child)
		value.make_read_only()
	elif value is Array:
		if value.is_read_only(): return
		for child: Variant in value: freeze_snapshot(child)
		value.make_read_only()
