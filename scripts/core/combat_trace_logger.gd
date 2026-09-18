class_name CombatTraceLogger
extends RefCounted

const SCHEMA_VERSION := 1
const MAX_TRACE_BYTES := 64 * 1024 * 1024
const ENVIRONMENT_FLAG := "STARHOME_COMBAT_TRACE"

static var _initialized := false
static var _enabled := false
static var _trace_path := ""
static var _writer: BackgroundFileWriter
static var _stopped := false
static var _write_warning_emitted := false
static var _path_announced := false


## 显式配置本进程的战斗诊断日志，主要供自动测试或发布包临时启用。
## [param enabled] 是否允许写入诊断记录。
## [param path_override] 可选输出路径；为空时按进程和启动时间生成 `user://diagnostics` 文件。
static func configure(enabled: bool, path_override: String = "") -> void:
	shutdown()
	_stopped = false
	_initialized = true
	_enabled = enabled
	_trace_path = path_override
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


## 冻结一条战斗诊断并交给后台线程，不在游戏帧中打开或刷新文件。
## [param side] 客户端、服务端或传输边界。[param stage] 链路阶段。[param fields] 当时的业务字段。
static func record(side: StringName, stage: StringName, fields: Dictionary = {}) -> void:
	if not is_enabled() or _stopped: return
	_ensure_trace_path()
	if _writer == null: return
	var entry := {
		"schema_version": SCHEMA_VERSION,
		"unix_time_ms": roundi(Time.get_unix_time_from_system() * 1000.0),
		"monotonic_time_ms": Time.get_ticks_msec(),
		"process_id": OS.get_process_id(),
		"side": String(side), "stage": String(stage), "fields": _json_safe(fields),
	}
	var accepted := _writer.enqueue_trace(ProjectSettings.globalize_path(_trace_path), entry, MAX_TRACE_BYTES)
	var result := _writer.last_result()
	if (accepted != OK or not result.is_ok) and not _write_warning_emitted:
		_write_warning_emitted = true
		push_warning("战斗日志后台写入异常或队列已满：%s" % _trace_path)


## 在加载场景前启动诊断线程，保留调试构建的默认开启规则。
static func start() -> void:
	if is_enabled() and not _stopped: _ensure_trace_path()


## 显式等待当前日志完成，供验收与人工读取使用；战斗逻辑不得调用。
## 返回后台落盘结果。
static func flush() -> DomainResult:
	return _writer.flush() if _writer != null else DomainResult.ok()


## 正常退出时排空日志并回收线程，之后到来的记录不再启动新线程。
## 返回最终写盘状态。
static func shutdown() -> DomainResult:
	_stopped = true
	var result: DomainResult = _writer.close() if _writer != null else DomainResult.ok()
	_writer = null
	return result


## 从构建类型和环境变量计算默认启用状态。
static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_enabled = OS.is_debug_build()
	if OS.has_environment(ENVIRONMENT_FLAG):
		var flag := OS.get_environment(ENVIRONMENT_FLAG).strip_edges().to_lower()
		_enabled = flag not in ["", "0", "false", "off", "no"]


## 生成本进程输出路径并启动后台所有者；目录创建和文件打开都由工作线程执行。
static func _ensure_trace_path() -> void:
	if _stopped: return
	if _trace_path.is_empty():
		_trace_path = "user://diagnostics/combat_trace_%d_%d.jsonl" % [floori(Time.get_unix_time_from_system()), OS.get_process_id()]
	if _writer != null: return
	_writer = BackgroundFileWriter.new()
	if _writer.start() != OK:
		_writer = null
		_enabled = false
		push_warning("无法启动战斗日志后台线程")
		return
	if not _path_announced:
		_path_announced = true
		print("战斗诊断日志：%s" % ProjectSettings.globalize_path(_trace_path))


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
