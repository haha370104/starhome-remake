class_name DomainResult
extends RefCounted

var is_ok: bool
var error_code: StringName
var error_message: String
var value: Variant


## 使用调用方参数初始化当前实例。
## [param result_is_ok] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param result_value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param result_error_code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param result_error_message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
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


## 执行 `ok` 对应的模块操作。
## [param result_value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
static func ok(result_value: Variant = null):
	return load("res://scripts/core/domain_result.gd").new(true, result_value)


## 执行 `failure` 对应的模块操作。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
static func failure(code: StringName, message: String):
	return load("res://scripts/core/domain_result.gd").new(false, null, code, message)
