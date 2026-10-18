extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证关闭成本、有界统计、跨线程安全和最终报告落盘。
func _initialize() -> void:
	call_deferred("_run")


## 使用隔离报告路径验证真实后台队列，不修改人物存档。
func _run() -> void:
	var path := ProjectSettings.globalize_path("user://telemetry-test.json")
	PerformanceTelemetry.configure(false, path)
	_check(PerformanceTelemetry.measure(&"off") == null, "关闭不创建计时对象")
	PerformanceTelemetry.record_duration(&"off", 10)
	PerformanceTelemetry.increment(&"off")
	PerformanceTelemetry.submit_report()
	_check(PerformanceTelemetry.snapshot().durations.is_empty() and not FileAccess.file_exists(path), "关闭不采集不写文件")
	_check(PerformanceTelemetry.configure(true, path, {"scenario": "unit"}) == OK, "开启后台报告")
	for value in range(1, 101): PerformanceTelemetry.record_duration(&"known", value)
	for value in range(PerformanceTelemetry.MAX_SAMPLES + 2): PerformanceTelemetry.record_duration(&"bounded", value)
	_early_return()
	var workers: Array[Thread] = []
	for index in 4:
		var thread := Thread.new()
		thread.start(_sample_thread)
		workers.append(thread)
	for thread: Thread in workers: thread.wait_to_finish()
	var snapshot := PerformanceTelemetry.snapshot()
	var report := PerformanceReportWriter.build_report(snapshot)
	_check(report.durations.known.p50_usec == 50 and report.durations.known.p95_usec == 95 and report.durations.known.p99_usec == 99, "已知分布百分位")
	_check(report.durations.known.mean_usec == 50.5 and report.durations.known.max_usec == 100, "累计均值与最大值")
	_check(report.durations.bounded.count == 2050 and report.durations.bounded.window_samples == 2048, "窗口有界且累计数不丢失")
	_check(report.durations.scope.count == 1 and report.durations.scope.max_usec > 0, "函数提前返回仍完成计时")
	_check(report.durations.thread.count == 400 and report.counters.thread == 400, "多线程记录无丢失")
	for index in range(PerformanceTelemetry.MAX_METRICS + 10):
		PerformanceTelemetry.record_duration(StringName("metric_%d" % index), 1)
	_check(PerformanceTelemetry.snapshot().durations.size() == PerformanceTelemetry.MAX_METRICS, "指标总数有界")
	PerformanceTelemetry.submit_report()
	_check(PerformanceTelemetry.close().is_ok, "正常关闭排空报告")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(saved is Dictionary and saved.durations.thread.count == 400 and saved.metadata.scenario == "unit", "磁盘报告完整")
	_check(not PerformanceTelemetry.is_enabled(), "关闭停止采样")
	print("Performance telemetry: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 验证计时对象在函数离开时提交，不需要每个返回分支手写收尾。
func _early_return() -> void:
	var _timing := PerformanceTelemetry.measure(&"scope")
	OS.delay_usec(100)
	return


## 在工作线程采样纯数值，不访问节点或引擎资源。
func _sample_thread() -> void:
	for index in 100:
		PerformanceTelemetry.record_duration(&"thread", index)
		PerformanceTelemetry.increment(&"thread")


## 汇总可开关统计的真实行为。
## [param condition] 实际结果。[param message] 期望说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
