class_name DomainResult
extends RefCounted

var is_ok: bool
var error_code: StringName
var error_message: String
var value: Variant


## Initializes a new instance with its required state.
## [param result_is_ok] Input value consumed by the operation.
## [param result_value] Input value consumed by the operation.
## [param result_error_code] Diagnostic value associated with the operation.
## [param result_error_message] Diagnostic value associated with the operation.
func _init(
	result_is_ok: bool,
	result_value: Variant = null,
	result_error_code: StringName = &"",
	result_error_message: String = "",
) -> void:
	is_ok = result_is_ok
	value = result_value
	error_code = result_error_code
	error_message = result_error_message


## Performs the `ok` operation.
## [param result_value] Input value consumed by the operation.
## Returns the result produced by the operation.
static func ok(result_value: Variant = null):
	return load("res://scripts/core/domain_result.gd").new(true, result_value)


## Performs the `failure` operation.
## [param code] Stable identifier of the target value.
## [param message] Serialized input received at the subsystem boundary.
## Returns the result produced by the operation.
static func failure(code: StringName, message: String):
	return load("res://scripts/core/domain_result.gd").new(false, null, code, message)
