class_name ContractValidation
extends RefCounted

const ErrorCodes = preload("res://scripts/network/contracts/network_error_codes.gd")
const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")


## 执行 `require_dictionary` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param context] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func require_dictionary(value: Variant, context: String):
	if typeof(value) != TYPE_DICTIONARY:
		return Result.failure(ErrorCodes.INVALID_PAYLOAD, "%s must be a Dictionary" % context)
	return Result.ok(value)


## 执行 `require_only_fields` 对应的模块操作。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param allowed_fields] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param context] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func require_only_fields(
	payload: Dictionary,
	allowed_fields: Array[StringName],
	context: String,
):
	for raw_field: Variant in payload.keys():
		if typeof(raw_field) != TYPE_STRING and typeof(raw_field) != TYPE_STRING_NAME:
			return Result.failure(
				ErrorCodes.INVALID_PAYLOAD,
				"%s contains a non-string field name" % context,
			)
		var field_name := StringName(raw_field)
		if field_name not in allowed_fields:
			return Result.failure(
				ErrorCodes.INVALID_PAYLOAD,
				"%s contains an unknown field: %s" % [context, field_name],
			)
	return Result.ok(payload)


## 执行 `require_field` 对应的模块操作。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param field_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func require_field(payload: Dictionary, field_name: StringName):
	if not payload.has(field_name):
		return Result.failure(ErrorCodes.MISSING_FIELD, "Missing field: %s" % field_name)
	return Result.ok(payload[field_name])


## 执行 `require_integer` 对应的模块操作。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param field_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param minimum] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param maximum] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func require_integer(payload: Dictionary, field_name: StringName, minimum: int, maximum: int):
	var field_result = require_field(payload, field_name)
	if not field_result.is_ok:
		return field_result
	if typeof(field_result.value) != TYPE_INT:
		return Result.failure(ErrorCodes.INVALID_FIELD_TYPE, "%s must be an integer" % field_name)
	var value: int = field_result.value
	if value < minimum or value > maximum:
		return Result.failure(ErrorCodes.VALUE_OUT_OF_RANGE, "%s is out of range" % field_name)
	return Result.ok(value)


## 执行 `require_number` 对应的模块操作。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param field_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param minimum] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param maximum] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func require_number(payload: Dictionary, field_name: StringName, minimum: float, maximum: float):
	var field_result = require_field(payload, field_name)
	if not field_result.is_ok:
		return field_result
	var value_type: int = typeof(field_result.value)
	if value_type != TYPE_INT and value_type != TYPE_FLOAT:
		return Result.failure(ErrorCodes.INVALID_FIELD_TYPE, "%s must be numeric" % field_name)
	var value: float = float(field_result.value)
	if not is_finite(value) or value < minimum or value > maximum:
		return Result.failure(ErrorCodes.VALUE_OUT_OF_RANGE, "%s is out of range" % field_name)
	return Result.ok(value)


## 执行 `require_identifier` 对应的模块操作。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param field_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func require_identifier(payload: Dictionary, field_name: StringName):
	var field_result = require_field(payload, field_name)
	if not field_result.is_ok:
		return field_result
	if typeof(field_result.value) != TYPE_STRING and typeof(field_result.value) != TYPE_STRING_NAME:
		return Result.failure(ErrorCodes.INVALID_FIELD_TYPE, "%s must be a string" % field_name)
	var value := String(field_result.value)
	if value.is_empty() or value.length() > Protocol.MAX_IDENTIFIER_LENGTH:
		return Result.failure(ErrorCodes.INVALID_IDENTIFIER, "%s is not a valid identifier" % field_name)
	for character: String in value:
		var code := character.unicode_at(0)
		var valid := (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or character in ["_", "-", ".", ":"]
		)
		if not valid:
			return Result.failure(ErrorCodes.INVALID_IDENTIFIER, "%s contains invalid characters" % field_name)
	return Result.ok(value)


## 执行 `require_string` 对应的模块操作。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param field_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param minimum_length] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param maximum_length] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func require_string(
	payload: Dictionary,
	field_name: StringName,
	minimum_length: int,
	maximum_length: int,
):
	var field_result = require_field(payload, field_name)
	if not field_result.is_ok:
		return field_result
	if typeof(field_result.value) != TYPE_STRING and typeof(field_result.value) != TYPE_STRING_NAME:
		return Result.failure(ErrorCodes.INVALID_FIELD_TYPE, "%s must be a string" % field_name)
	var value := String(field_result.value)
	if value.length() < minimum_length or value.length() > maximum_length:
		return Result.failure(ErrorCodes.VALUE_OUT_OF_RANGE, "%s has an invalid length" % field_name)
	return Result.ok(value)


## 执行 `require_vector2` 对应的模块操作。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param field_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func require_vector2(payload: Dictionary, field_name: StringName):
	var field_result = require_field(payload, field_name)
	if not field_result.is_ok:
		return field_result
	if typeof(field_result.value) != TYPE_DICTIONARY:
		return Result.failure(ErrorCodes.INVALID_FIELD_TYPE, "%s must be a coordinate Dictionary" % field_name)
	var coordinate: Dictionary = field_result.value
	var fields_result = require_only_fields(coordinate, [&"x", &"y"], String(field_name))
	if not fields_result.is_ok:
		return fields_result
	var x_result = require_number(
		coordinate,
		&"x",
		-Protocol.MAX_WORLD_COORDINATE,
		Protocol.MAX_WORLD_COORDINATE,
	)
	if not x_result.is_ok:
		return x_result
	var y_result = require_number(
		coordinate,
		&"y",
		-Protocol.MAX_WORLD_COORDINATE,
		Protocol.MAX_WORLD_COORDINATE,
	)
	if not y_result.is_ok:
		return y_result
	return Result.ok(Vector2(float(x_result.value), float(y_result.value)))


## 执行 `vector2_to_dictionary` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
static func vector2_to_dictionary(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
