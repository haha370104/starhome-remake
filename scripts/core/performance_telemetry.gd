class_name PerformanceTelemetry
extends RefCounted

const MAX_METRICS := 128
const MAX_SAMPLES := 2048
static var _enabled := false
static var _mutex := Mutex.new()
static var _durations: Dictionary = {}
static var _counters: Dictionary = {}
static var _gauges: Dictionary = {}
static var _metadata: Dictionary = {}
static var _writer: PerformanceReportWriter
static var _path := ""

class Span extends RefCounted:
	var metric: StringName
	var started: int
	## 函数局部计时对象释放时记录耗时，提前返回也会执行。
	## [param what] 引擎生命周期通知。
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			PerformanceTelemetry.record_duration(metric, Time.get_ticks_usec() - started)


## 在启动或独立基准开始时配置统计，关闭时不创建线程或文件。
## [param enabled] 显式开关。[param path] 报告路径。[param metadata] 本轮测试条件。
## 返回后台报告线程的初始化结果。
static func configure(enabled: bool, path: String = "", metadata: Dictionary = {}) -> Error:
	close()
	_mutex.lock()
	_durations.clear()
	_counters.clear()
	_gauges.clear()
	_metadata = metadata.duplicate(true)
	_mutex.unlock()
	if not enabled: return OK
	_path = ProjectSettings.globalize_path(path if not path.is_empty() else "user://diagnostics/performance_%d_%d.json" % [int(Time.get_unix_time_from_system()), OS.get_process_id()])
	_writer = PerformanceReportWriter.new()
	var error := _writer.start()
	if error != OK:
		_writer = null
		return error
	_enabled = true
	return OK


## 热路径直接读取配置标志；关闭时不加锁、不取时钟。
## 返回当前统计是否开启。
static func is_enabled() -> bool:
	return _enabled


## 创建函数局部计时范围，关闭时直接返回空值。
## [param metric] 固定语义指标名，不能包含实体身份。
## 返回生命周期计时对象，调用方以局部变量持有到函数结束。
static func measure(metric: StringName) -> Span:
	if not _enabled: return null
	var span := Span.new()
	span.metric = metric
	span.started = Time.get_ticks_usec()
	return span


## 在有界环形窗口采样，累计次数、均值和最大值覆盖整轮。
## [param metric] 固定指标名。[param usec] 微秒耗时，负数忽略。
static func record_duration(metric: StringName, usec: int) -> void:
	if not _enabled or usec < 0: return
	_mutex.lock()
	if not _durations.has(metric):
		if _durations.size() >= MAX_METRICS:
			_mutex.unlock()
			return
		_durations[metric] = {"values": [], "count": 0, "total": 0, "max": 0}
	var row: Dictionary = _durations[metric]
	var values: Array = row.values
	if values.size() < MAX_SAMPLES: values.append(usec)
	else: values[int(row.count) % MAX_SAMPLES] = usec
	row.count += 1
	row.total += usec
	row.max = maxi(row.max, usec)
	_mutex.unlock()


## 累计命中、未命中等固定名称事件，关闭时不分配容器。
## [param key] 事件名。[param amount] 增量。
static func increment(key: StringName, amount: int = 1) -> void:
	if not _enabled: return
	_mutex.lock()
	if _counters.has(key) or _counters.size() < MAX_METRICS:
		_counters[key] = int(_counters.get(key, 0)) + amount
	_mutex.unlock()


## 记录最近一次对象数量或占用，禁止使用角色ID作为指标名。
## [param key] 固定名称。[param value] 有限数值。
static func set_gauge(key: StringName, value: float) -> void:
	if not _enabled or not is_finite(value): return
	_mutex.lock()
	if _gauges.has(key) or _gauges.size() < MAX_METRICS: _gauges[key] = value
	_mutex.unlock()


## 原子冻结少量统计值，排序和JSON序列化由后台线程承担。
## 返回不含场景、角色或资源对象的独立快照。
static func snapshot() -> Dictionary:
	_mutex.lock()
	var result := {"metadata": _metadata.duplicate(true), "durations": _durations.duplicate(true),
		"counters": _counters.duplicate(true), "gauges": _gauges.duplicate(true)}
	_mutex.unlock()
	return result


## 将最新统计入队，相同路径的旧报告自动合并，不在游戏帧等待磁盘。
## 返回入队是否成功。
static func submit_report() -> Error:
	if not _enabled or _writer == null: return OK
	return _writer.enqueue_snapshot(_path, snapshot())


## 正常退出时写入最终报告并回收低优先级线程；重复关闭安全。
## 返回最终实际写盘结果。
static func close() -> DomainResult:
	if _writer == null:
		_enabled = false
		return DomainResult.ok()
	submit_report()
	_enabled = false
	var result := _writer.close()
	_writer = null
	return result
