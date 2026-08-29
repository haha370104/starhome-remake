class_name CombatTraceLogger
extends RefCounted

const SCHEMA_VERSION := 1
const MAX_TRACE_BYTES := 64 * 1024 * 1024
const ENVIRONMENT_FLAG := "STARHOME_COMBAT_TRACE"

static var _initialized := false
static var _enabled := false
static var _trace_path := ""
static var _limit_warning_emitted := false
static var _write_warning_emitted := false
static var _path_announced := false


## 显式配置本进程的战斗诊断日志，主要供自动测试或发布包临时启用。
## [param enabled] 是否允许写入诊断记录。
## [param path_override] 可选输出路径；为空时按进程和启动时间生成 `user://diagnostics` 文件。
static func configure(enabled: bool, path_override: String = "") -> void:
	_initialized = true
	_enabled = enabled
	_trace_path = path_override
	_limit_warning_emitted = false
	_write_warning_emitted = false
	_path_announced = false
	if _enabled:
		_ensure_trace_path()


## 判断当前进程是否启用了战斗诊断。
## 返回启用状态。
## 设计：调试构建默认启用；发布构建可通过 `STARHOME_COMBAT_TRACE=1` 临时开启。
static func is_enabled() -> bool:
	_ensure_initialized()
	return _enabled


## 查询当前进程实际使用的 JSONL 日志路径。
## 返回空字符串表示诊断未启用或目录创建失败。
static func trace_path() -> String:
	_ensure_initialized()
	if _enabled:
		_ensure_trace_path()
	return _trace_path


## 追加一条结构化战斗诊断记录并立即落盘。
## [param side] 事件发生边界，例如 `client`、`server` 或 `transport`。
## [param stage] 射击链路阶段，例如客户端预测碰撞或服务端权威结算。
## [param fields] 与本阶段有关的业务字段；向量和 StringName 会被转换为 JSON 安全值。
static func record(side: StringName, stage: StringName, fields: Dictionary = {}) -> void:
	if not is_enabled():
		return
	_ensure_trace_path()
	if _trace_path.is_empty():
		return
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(_trace_path) else FileAccess.WRITE
	var file := FileAccess.open(_trace_path, mode)
	if file == null:
		if not _write_warning_emitted:
			_write_warning_emitted = true
			push_warning("无法写入战斗诊断日志：%s" % ProjectSettings.globalize_path(_trace_path))
		return
	if not _path_announced:
		_path_announced = true
		print("战斗诊断日志：%s" % ProjectSettings.globalize_path(_trace_path))
	if file.get_length() >= MAX_TRACE_BYTES:
		file.close()
		if not _limit_warning_emitted:
			_limit_warning_emitted = true
			push_warning("战斗诊断日志已达到 64 MiB 上限：%s" % ProjectSettings.globalize_path(_trace_path))
		return
	file.seek_end()
	var entry := {
		"schema_version": SCHEMA_VERSION,
		"unix_time_ms": roundi(Time.get_unix_time_from_system() * 1000.0),
		"monotonic_time_ms": Time.get_ticks_msec(),
		"process_id": OS.get_process_id(),
		"side": String(side),
		"stage": String(stage),
		"fields": _json_safe(fields),
	}
	file.store_line(JSON.stringify(entry))
	file.flush()
	file.close()


## 从构建类型和环境变量计算默认启用状态。
static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_enabled = OS.is_debug_build()
	if OS.has_environment(ENVIRONMENT_FLAG):
		var flag := OS.get_environment(ENVIRONMENT_FLAG).strip_edges().to_lower()
		_enabled = flag not in ["", "0", "false", "off", "no"]


## 创建本次进程唯一的输出路径，并把绝对位置打印到启动终端。
static func _ensure_trace_path() -> void:
	if not _trace_path.is_empty():
		return
	var directory := "user://diagnostics"
	var absolute_directory := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		_enabled = false
		return
	_trace_path = directory.path_join(
		"combat_trace_%d_%d.jsonl" % [floori(Time.get_unix_time_from_system()), OS.get_process_id()]
	)


## 递归转换诊断字段，确保任意合法领域值都能写入 JSONL。
## [param value] 字典、数组、向量、StringName 或标量值。
## 返回只含 JSON 支持类型的等价值。
static func _json_safe(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is StringName:
		return String(value)
	if value is Dictionary:
		var converted := {}
		for key: Variant in value:
			converted[String(key)] = _json_safe(value[key])
		return converted
	if value is Array:
		var converted: Array = []
		for item: Variant in value:
			converted.append(_json_safe(item))
		return converted
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	return str(value)
