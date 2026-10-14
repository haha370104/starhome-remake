class_name SpriteResourceQueue
extends Node

signal texture_ready(path: String, texture: Texture2D)
signal texture_failed(path: String)

const MAX_REQUESTS := 128
const UPLOAD_BUDGET_USEC := 2000
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _uploaded := Semaphore.new()
var _jobs: Array[String] = []
var _results: Array[Dictionary] = []
var _pending: Dictionary[String, bool] = {}
var _imported: Dictionary[String, bool] = {}
var _stopping := false


## 去重排队；导入纹理交给 Godot，包内图片在低优先级线程读取解码。
## [param path] 本地已登记资源路径。
## 返回接收结果，所有回调延迟至调用结束后。
func request(path: String) -> Error:
	if _pending.has(path): return OK
	var cached := RuntimeTextureLoader.cache.fetch(path)
	if cached != null:
		_publish_cached.call_deferred(path, cached)
		return OK
	if _pending.size() >= MAX_REQUESTS: return ERR_BUSY
	_pending[path] = true
	if ResourceLoader.exists(path):
		var result := ResourceLoader.load_threaded_request(path)
		if result != OK:
			_pending.erase(path)
			return result
		_imported[path] = true
	else:
		if not _thread.is_started():
			var result := _thread.start(_decode_loop, Thread.PRIORITY_LOW)
			if result != OK:
				_pending.erase(path)
				return result
		_mutex.lock()
		_jobs.append(path)
		_mutex.unlock()
		_wake.post()
	return OK


## 在主线程逐帧上传，单个大图上传不可中断；每帧最多两张且受软时间预算限制。
## [param _delta] 帧间隔，本队列按任务而非时间推进。
func _process(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	var count := 0
	for path: String in _imported.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
		var imported_texture: Texture2D
		if status == ResourceLoader.THREAD_LOAD_LOADED: imported_texture = ResourceLoader.load_threaded_get(path) as Texture2D
		_imported.erase(path)
		_publish(path, imported_texture)
		count += 1
		if count >= 2 or Time.get_ticks_usec() - started >= UPLOAD_BUDGET_USEC: return
	_mutex.lock()
	var result: Dictionary = _results.pop_front() if not _results.is_empty() else {}
	_mutex.unlock()
	if result.is_empty(): return
	var texture: Texture2D
	if result.image != null:
		var _timing := PerformanceTelemetry.measure(&"resource_texture_upload")
		texture = ImageTexture.create_from_image(result.image)
	_uploaded.post()
	_publish(result.path, texture)


## 工作线程只操作文件、独立 Image 和受锁保护的队列；待上传 Image 最多一张。
func _decode_loop() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		if _stopping:
			_mutex.unlock()
			return
		var path := _jobs.pop_front() as String
		_mutex.unlock()
		var decoded := RuntimeTextureLoader.decode_image(path)
		_mutex.lock()
		_results.append({"path": path, "image": decoded})
		_mutex.unlock()
		_uploaded.wait()


## 主线程发布完成结果并释放请求状态。
## [param path] 请求路径。[param texture] 成功纹理或 null。
func _publish(path: String, texture: Texture2D) -> void:
	_pending.erase(path)
	if texture == null: texture_failed.emit(path)
	else:
		RuntimeTextureLoader.cache.retain(path, texture)
		texture_ready.emit(path, texture)


## 延迟发布缓存命中，保持和异步加载相同的信号时序。
## [param path] 请求路径。[param texture] 已缓存纹理。
func _publish_cached(path: String, texture: Texture2D) -> void:
	if is_inside_tree(): texture_ready.emit(path, texture)


## 退出时唤醒可能等待上传的线程，并在节点释放前等待当前解码结束。
func _exit_tree() -> void:
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	_uploaded.post()
	_wake.post()
	if _thread.is_started(): _thread.wait_to_finish()
