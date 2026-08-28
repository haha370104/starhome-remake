class_name NetworkErrorCodes
extends RefCounted

const INVALID_PAYLOAD: StringName = &"network.invalid_payload"
const MISSING_FIELD: StringName = &"network.missing_field"
const INVALID_FIELD_TYPE: StringName = &"network.invalid_field_type"
const VALUE_OUT_OF_RANGE: StringName = &"network.value_out_of_range"
const INVALID_IDENTIFIER: StringName = &"network.invalid_identifier"
const UNSUPPORTED_PROTOCOL_VERSION: StringName = &"network.unsupported_protocol_version"
const CONTENT_VERSION_MISMATCH: StringName = &"network.content_version_mismatch"
const UNKNOWN_MESSAGE_TYPE: StringName = &"network.unknown_message_type"
const STALE_SEQUENCE: StringName = &"network.stale_sequence"
const MAP_TRANSITION_SOURCE_MISMATCH: StringName = &"map_transition.source_mismatch"
const MAP_TRANSITION_UNKNOWN_EXIT: StringName = &"map_transition.unknown_exit"
const MAP_TRANSITION_DISABLED: StringName = &"map_transition.disabled"
const MAP_TRANSITION_TOO_FAR: StringName = &"map_transition.too_far_from_exit"
const MAP_TRANSITION_TARGET_UNRESOLVED: StringName = &"map_transition.target_unresolved"
const MAP_TRANSITION_ENTRY_MISMATCH: StringName = &"map_transition.entry_mismatch"
const MAP_TRANSITION_DESTINATION_BLOCKED: StringName = &"map_transition.destination_blocked"


## 执行 `all` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func all() -> Array[StringName]:
	return [
		INVALID_PAYLOAD,
		MISSING_FIELD,
		INVALID_FIELD_TYPE,
		VALUE_OUT_OF_RANGE,
		INVALID_IDENTIFIER,
		UNSUPPORTED_PROTOCOL_VERSION,
		CONTENT_VERSION_MISMATCH,
		UNKNOWN_MESSAGE_TYPE,
		STALE_SEQUENCE,
		MAP_TRANSITION_SOURCE_MISMATCH,
		MAP_TRANSITION_UNKNOWN_EXIT,
		MAP_TRANSITION_DISABLED,
		MAP_TRANSITION_TOO_FAR,
		MAP_TRANSITION_TARGET_UNRESOLVED,
		MAP_TRANSITION_ENTRY_MISMATCH,
		MAP_TRANSITION_DESTINATION_BLOCKED,
	]
