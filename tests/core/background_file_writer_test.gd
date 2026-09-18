extends SceneTree

class BlockedWriter extends BackgroundFileWriter:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var writes := 0
	## 阻塞首个真实磁盘任务，让主线程能够确定性验证独立入队。
	## [param job] 队列冻结的数据。
	## 返回真实写盘结果。
	func _write_job(job: Dictionary) -> DomainResult:
		writes += 1
		if writes == 1:
			entered.post()
			release.wait()
		return super(job)

var checks := 0
var failures: Array[String] = []


## 检验后台阻塞、顺序、隔离、快照合并及正常关闭排空。
func _initialize() -> void:
	var base := ProjectSettings.globalize_path("user://background-test")
	var writer := BlockedWriter.new()
	_check(writer.start() == OK, "启动文件线程")
	writer.enqueue_snapshot(base + "/state.json", {"revision": 0})
	writer.entered.wait()
	var document := {"revision": 1, "nested": {"amount": 7}}
	_check(writer.enqueue_snapshot(base + "/state.json", document) == OK, "磁盘阻塞不阻塞主线程入队")
	document.nested.amount = 99
	for revision in range(2, 100):
		writer.enqueue_snapshot(base + "/state.json", {"revision": revision, "nested": {"amount": 7}})
	var fields := {"index": 0, "nested": {"amount": 7}}
	for index in 1000:
		fields.index = index
		_check(writer.enqueue_trace(base + "/trace.jsonl", fields, 1024 * 1024) == OK, "持续记录入队")
	fields.nested.amount = 99
	_check(not FileAccess.file_exists(base + "/state.json"), "任务尚未放行时磁盘仍无快照")
	writer.release.post()
	_check(writer.flush().is_ok, "检查点等待全部前序任务")
	_check(writer.writes == 3, "首份在途存档、最新合并存档和一个日志批次")
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "/state.json"))
	_check(stored.revision == 99 and stored.nested.amount == 7, "磁盘最后是最新完整快照")
	var lines := FileAccess.get_file_as_string(base + "/trace.jsonl").strip_edges().split("\n")
	_check(lines.size() == 1000, "不丢连续日志")
	for index in lines.size():
		var entry: Dictionary = JSON.parse_string(lines[index])
		_check(entry.index == index and entry.nested.amount == 7, "日志有序且字段在入队时冻结")
	writer.enqueue_trace(base + "/trace.jsonl", {"index": 1000}, 1024 * 1024)
	_check(writer.close().is_ok, "正常关闭排空尾部日志")
	_check(writer.close().is_ok, "重复关闭不重复等待线程")
	_check(FileAccess.get_file_as_string(base + "/trace.jsonl").strip_edges().split("\n").size() == 1001, "退出尾部记录已落盘")
	_check(writer.enqueue_snapshot(base + "/state.json", {}) == ERR_UNAVAILABLE, "关闭后拒绝新任务")
	var limited := BackgroundFileWriter.new()
	limited.start()
	limited.enqueue_trace(base + "/limited.jsonl", {"index": 1}, 1)
	limited.enqueue_trace(base + "/limited.jsonl", {"index": 2}, 1)
	_check(limited.flush().error_code == &"diagnostics.size_limit", "日志容量限制保留")
	limited.close()
	for failure in failures: push_error(failure)
	print("BACKGROUND_FILE_WRITER_%s (%d checks)" % ["OK" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


## 汇总实际线程和磁盘断言。
## [param condition] 断言结果。[param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
