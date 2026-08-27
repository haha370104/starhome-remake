class_name JsonConfigLoader
extends RefCounted

const DomainResult = preload("res://scripts/core/domain_result.gd")


## Loads and validates the requested resource data.
## [param path] Resource or movement path consumed by the operation.
## Returns A domain result containing either the computed value or a validation error.
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
