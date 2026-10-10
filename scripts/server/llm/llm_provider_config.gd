class_name LlmProviderConfig
extends RefCounted

const Result := preload("res://scripts/core/domain_result.gd")

var model := ""
var model_reasoning_effort := "minimal"
var base_url := ""
var wire_api := "responses"
var api_key := ""
var context_compact_threshold := 247520


static func default_path() -> String:
	var config_home := OS.get_environment("XDG_CONFIG_HOME").strip_edges()
	if config_home.is_empty() or not config_home.is_absolute_path():
		var home := OS.get_environment("HOME").strip_edges()
		config_home = OS.get_user_data_dir() if home.is_empty() else home.path_join(".config")
	return config_home.path_join("starhome-remake/llm/config.toml")


static func load_file(path := "") -> DomainResult:
	if path.is_empty():
		path = default_path()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure(&"llm.config_missing", "LLM config file could not be opened: " + path)
	var parsed := _parse_toml(file.get_as_text())
	if not parsed.is_ok:
		return parsed
	var values: Dictionary = parsed.value
	var auth_path := path.get_base_dir() + "/auth.json"
	if String(values.get("OPENAI_API_KEY", values.get("api_key", ""))).is_empty() \
			and FileAccess.file_exists(auth_path):
		var auth_file := FileAccess.open(auth_path, FileAccess.READ)
		var auth_value: Variant = JSON.parse_string(auth_file.get_as_text()) if auth_file != null else null
		if auth_value is Dictionary:
			for key: Variant in auth_value.keys():
				values[String(key)] = auth_value[key]
	return from_dictionary(values)


static func from_dictionary(values: Dictionary) -> DomainResult:
	var config := LlmProviderConfig.new()
	config.model = String(values.get("model", "")).strip_edges()
	config.model_reasoning_effort = String(values.get("model_reasoning_effort", "minimal")).strip_edges()
	config.base_url = String(values.get("base_url", "")).strip_edges().trim_suffix("/")
	config.wire_api = String(values.get("wire_api", "responses")).strip_edges().to_lower()
	config.api_key = String(values.get("OPENAI_API_KEY", values.get("api_key", ""))).strip_edges()
	var threshold: Variant = values.get("context_compact_threshold", config.context_compact_threshold)
	if typeof(threshold) != TYPE_INT or threshold < 0:
		return Result.failure(&"llm.config_invalid", "context_compact_threshold must be a non-negative integer")
	config.context_compact_threshold = threshold
	if config.model.is_empty():
		return Result.failure(&"llm.config_invalid", "model is required")
	if config.base_url.is_empty():
		return Result.failure(&"llm.config_invalid", "base_url is required")
	if config.api_key.is_empty():
		return Result.failure(&"llm.config_invalid", "OPENAI_API_KEY is required")
	if config.wire_api != "responses":
		return Result.failure(&"llm.config_invalid", "only the responses wire_api is supported")
	if config.model_reasoning_effort.is_empty():
		return Result.failure(&"llm.config_invalid", "model_reasoning_effort cannot be empty")
	return Result.ok(config)


static func _parse_toml(text: String) -> DomainResult:
	var values: Dictionary = {}
	for raw_line: String in text.split("\n"):
		var line := _strip_comment(raw_line).strip_edges()
		if line.is_empty() or line.begins_with("["):
			continue
		var separator := line.find("=")
		if separator <= 0:
			return Result.failure(&"llm.config_invalid", "invalid config line")
		var key := line.substr(0, separator).strip_edges()
		var raw_value := line.substr(separator + 1).strip_edges()
		if key.is_empty() or raw_value.is_empty():
			return Result.failure(&"llm.config_invalid", "invalid config key or value")
		values[key] = _parse_value(raw_value)
	return Result.ok(values)


static func _strip_comment(line: String) -> String:
	var quoted := false
	for index: int in range(line.length()):
		var character := line.substr(index, 1)
		if character == "\"" and (index == 0 or line.substr(index - 1, 1) != "\\"):
			quoted = not quoted
		elif character == "#" and not quoted:
			return line.substr(0, index)
	return line


static func _parse_value(raw_value: String) -> Variant:
	if raw_value.begins_with("\"") and raw_value.ends_with("\""):
		var parsed: Variant = JSON.parse_string(raw_value)
		return parsed if parsed != null else raw_value.substr(1, raw_value.length() - 2)
	if raw_value == "true": return true
	if raw_value == "false": return false
	if raw_value.is_valid_int(): return int(raw_value)
	if raw_value.is_valid_float(): return float(raw_value)
	return raw_value
