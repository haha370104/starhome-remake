class_name JsonConfigLoader
extends RefCounted

const DomainResult = preload("res://scripts/core/domain_result.gd")


## 加载并校验 `load_dictionary` 对应的模块状态。
## [param path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func load_dictionary(path: String) -> DomainResult:
	if not FileAccess.file_exists(path):
		return DomainResult.failure(&"config_not_found", "Configuration does not exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return DomainResult.failure(
			&"config_open_failed",
			"Configuration cannot be opened: %s" % path,
		)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return DomainResult.failure(
			&"config_invalid_json",
			"Invalid JSON at line %d in %s: %s" % [parser.get_error_line(), path, parser.get_error_message()],
		)
	if not parser.data is Dictionary:
		return DomainResult.failure(&"config_wrong_root_type", "Configuration root must be an object: %s" % path)
	return DomainResult.ok(parser.data)
