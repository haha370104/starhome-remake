class_name SequenceGate
extends RefCounted

const ErrorCodes = preload("res://scripts/network/contracts/network_error_codes.gd")
const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")

var _last_accepted_by_stream: Dictionary = {}


## 执行 `accept` 对应的模块操作。
## [param stream_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func accept(stream_id: StringName, sequence: int):
	if stream_id.is_empty():
		return Result.failure(ErrorCodes.INVALID_IDENTIFIER, "Sequence stream ID cannot be empty")
	if sequence < Protocol.MIN_SEQUENCE or sequence > Protocol.MAX_SEQUENCE:
		return Result.failure(ErrorCodes.VALUE_OUT_OF_RANGE, "Sequence is out of range")
	if not would_accept(stream_id, sequence):
		return Result.failure(
			ErrorCodes.STALE_SEQUENCE,
			"Sequence %d is not newer than %d" % [sequence, last_accepted(stream_id)],
		)
	_last_accepted_by_stream[stream_id] = sequence
	return Result.ok(sequence)


## 执行 `would_accept` 对应的模块操作。
## [param stream_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func would_accept(stream_id: StringName, sequence: int) -> bool:
	if stream_id.is_empty() or sequence < Protocol.MIN_SEQUENCE or sequence > Protocol.MAX_SEQUENCE:
		return false
	return not _last_accepted_by_stream.has(stream_id) or sequence > int(_last_accepted_by_stream[stream_id])


## 执行 `last_accepted` 对应的模块操作。
## [param stream_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func last_accepted(stream_id: StringName) -> int:
	return int(_last_accepted_by_stream.get(stream_id, -1))


## 执行 `reset` 对应的模块操作。
## [param stream_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func reset(stream_id: StringName) -> void:
	_last_accepted_by_stream.erase(stream_id)


## 执行 `reset_all` 对应的模块操作。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func reset_all() -> void:
	_last_accepted_by_stream.clear()
