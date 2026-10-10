class_name BackgroundFileWriter
extends RefCounted

const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")
const MAX_PENDING_TRACE_RECORDS := 8192
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _pending: Array[Dictionary] = []
var _closing := false
var _trace_count := 0
var _result: DomainResult = DomainResult.ok()
var _files: Dictionary = {}
var checkpoint_merge_count := 0
var background_write_count := 0
var last_write_bytes := 0


## 启动低优先级文件线程；线程只消费隔离数据，不访问场景或玩家领域对象。
## 返回线程创建结果。
func start() -> Error:
	return _thread.start(_run, Thread.PRIORITY_LOW)


## 合并尚未执行的同一路径存档，使队列最终写入最新完整快照。
## [param path] 原生绝对路径。[param document] 主线程生成的完整存档数据。
## [param transfer_ownership] 为 true 时调用方不得再修改该快照。
## 返回是否已接收入队；入队不代表已经落盘。
func enqueue_snapshot(path: String, document: Dictionary, transfer_ownership := false, ordered := false) -> Error:
	var snapshot := document if transfer_ownership else document.duplicate(true)
	var enqueued_at_usec := Time.get_ticks_usec()
	_mutex.lock()
	if _closing:
		_mutex.unlock()
		return ERR_UNAVAILABLE
	for index in range(_pending.size() - 1, -1, -1):
		if _pending[index].has("fence") or (ordered and _pending[index].get("kind") == "trace"): break
		if _pending[index].get("kind") == "snapshot" and _pending[index].path == path:
			_pending[index].document = snapshot
			_pending[index].enqueued_at_usec = enqueued_at_usec
			checkpoint_merge_count += 1
			PerformanceTelemetryScript.increment(&"autosave_checkpoint_merges")
			_mutex.unlock()
			return OK
	_pending.append({
		"kind": "snapshot", "path": path, "document": snapshot,
		"enqueued_at_usec": enqueued_at_usec,
	})
	_mutex.unlock()
	_wake.post()
	return OK


## 顺序接收日志快照，同一批记录共用文件句柄与一次刷新。
## [param path] 原生绝对路径。[param entry] 已冻结的JSON安全字段。[param maximum_bytes] 单文件容量限制。
## 返回入队结果；拥塞时明确拒绝，不在游戏帧中等待磁盘。
func enqueue_trace(path: String, entry: Dictionary, maximum_bytes: int) -> Error:
	var frozen := entry.duplicate(true)
	_mutex.lock()
	if _closing or _trace_count >= MAX_PENDING_TRACE_RECORDS:
		_mutex.unlock()
		return ERR_BUSY
	_trace_count += 1
	var was_empty := _pending.is_empty()
	if not _pending.is_empty() and _pending.back().get("kind") == "trace" and _pending.back().path == path:
		_pending.back().entries.append(frozen)
	else:
		_pending.append({"kind": "trace", "path": path, "entries": [frozen], "limit": maximum_bytes})
	_mutex.unlock()
	if was_empty: _wake.post()
	return OK


## 等待调用前的全部文件任务完成，仅供正常退出、显式诊断和测试使用。
## 返回最近一次实际写盘结果；战斗及普通存档不得调用此等待接口。
func flush() -> DomainResult:
	if not _thread.is_started(): return _result
	var fence := {"fence": Semaphore.new(), "result": DomainResult.ok()}
	_mutex.lock()
	_pending.append(fence)
	_mutex.unlock()
	_wake.post()
	(fence.fence as Semaphore).wait()
	return fence.result


## 查询上一次后台完成状态，不等待磁盘。
## 返回后台最近一次完成状态。
func last_result() -> DomainResult:
	_mutex.lock()
	var result := _result
	_mutex.unlock()
	return result


## 排空剩余任务并回收线程；重复关闭安全。
## 返回最后一次实际写盘结果。
func close() -> DomainResult:
	if not _thread.is_started(): return _result
	_mutex.lock()
	_closing = true
	_mutex.unlock()
	_wake.post()
	_thread.wait_to_finish()
	return _result


## 在低优先级线程按批次执行文件操作；锁只用于交换队列，不覆盖序列化或磁盘调用。
func _run() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		var closing := _closing
		_mutex.unlock()
		if not closing: _wait_for_checkpoint_batch()
		_mutex.lock()
		var batch := _pending
		_pending = []
		_trace_count = 0
		closing = _closing
		_mutex.unlock()
		for job: Dictionary in batch:
			if job.has("fence"):
				job.result = _result
				(job.fence as Semaphore).post()
				continue
			var written := _write_job(job)
			_mutex.lock()
			_result = written
			_mutex.unlock()
		if closing: break
	for file: FileAccess in _files.values(): file.close()
	_files.clear()


## 合并普通检查点；显式 flush fence 到达后立即开始写盘。
func _wait_for_checkpoint_batch() -> void:
	var deadline_usec := Time.get_ticks_usec() + 50000
	while Time.get_ticks_usec() < deadline_usec:
		_mutex.lock()
		var durable_fence_pending := false
		for job: Dictionary in _pending:
			if job.has("fence"):
				durable_fence_pending = true
				break
		_mutex.unlock()
		if durable_fence_pending:
			return
		OS.delay_msec(1)


## 执行一份已冻结的文件任务，提供窄测试接缝以模拟慢盘。
## [param job] 队列拥有的快照或JSONL批次。
## 返回实际文件操作结果。
func _write_job(job: Dictionary) -> DomainResult:
	if job.kind == "snapshot":
		PerformanceTelemetryScript.record_duration(
			&"autosave_background_queue_wait",
			Time.get_ticks_usec() - int(job.get("enqueued_at_usec", Time.get_ticks_usec())),
		)
		var encode_started_at := PerformanceTelemetryScript.begin(&"autosave_background_json_encode")
		var serialized := JSON.stringify(job.document)
		PerformanceTelemetryScript.end(&"autosave_background_json_encode", encode_started_at)
		last_write_bytes = serialized.to_utf8_buffer().size()
		var write_started_at := PerformanceTelemetryScript.begin(&"autosave_background_write")
		var written := AtomicJsonFile.write_serialized(job.path, serialized)
		PerformanceTelemetryScript.end(&"autosave_background_write", write_started_at)
		background_write_count += 1
		PerformanceTelemetryScript.increment(&"autosave_background_write_count")
		return written
	var path: String = job.path
	if not _files.has(path):
		if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
			return DomainResult.failure(&"diagnostics.storage_error", "cannot create trace directory")
		var opened := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		if opened == null: return DomainResult.failure(&"diagnostics.storage_error", "cannot open trace file")
		opened.seek_end()
		_files[path] = opened
	var file: FileAccess = _files[path]
	for entry: Dictionary in job.entries:
		if file.get_position() >= int(job.limit):
			file.flush()
			return DomainResult.failure(&"diagnostics.size_limit", "trace file reached size limit")
		file.store_line(JSON.stringify(entry))
	file.flush()
	return DomainResult.ok() if file.get_error() == OK else DomainResult.failure(&"diagnostics.storage_error", "cannot write trace file")
