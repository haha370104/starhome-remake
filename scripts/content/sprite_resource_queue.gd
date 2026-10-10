class_name SpriteResourceQueue
extends Node

const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")

var repository: AleSpriteRepository
var _pending: Dictionary[String, Array] = {}
var _requests: Dictionary[String, Dictionary] = {}
var _active_key := ""
var _task := -1
var _resource_path := ""
var _decoded: Dictionary = {}
var _build: AleSpriteRepository.AnimationBuild


## 去重请求或预取单帧；回调只在主线程调用。
## [param presentation] 图片或 ALE 单帧定义。[param callback] 可选的显示回调。
func request(presentation: Dictionary, callback: Callable = Callable()) -> void:
	var reference := String(presentation.get("ale_reference", ""))
	var path := String(presentation.get("icon", presentation.get("dialog_texture", presentation.get("texture", ""))))
	var frame := int(presentation.get("frame", 0))
	_enqueue("frame:%s|%s|%d" % [path, reference, frame], {"kind": "frame", "path": path,
		"definition": repository.resolve(reference) if not reference.is_empty() else {}, "frame": frame}, callback)


## 请求完整死亡动画，图集与构造后的帧由共享仓储缓存。
## [param reference] ALE 引用。[param prefix] 索引消歧前缀。[param callback] 可选主线程回调。
func request_animation(reference: String, prefix: String, callback: Callable = Callable()) -> void:
	var definition := repository.resolve(reference, prefix)
	if definition.is_empty():
		if callback.is_valid(): callback.call({})
		return
	var cached := repository.cached_animation(String(definition.logical_id))
	if not cached.is_empty():
		if callback.is_valid(): callback.call(cached)
		return
	_enqueue("animation:" + String(definition.logical_id), {"kind": "animation", "path": "", "definition": definition}, callback)


## 异步加载内容目录明确引用的 SpriteFrames。
## [param path] 受控资源路径。[param callback] 可选主线程回调。
func request_frames(path: String, callback: Callable = Callable()) -> void:
	_enqueue("resource:" + path, {"kind": "resource", "path": path, "definition": {}}, callback)


## 共享请求表和结果缓存，重复请求只增加仍有效的订阅者。
## [param key] 唯一资源键。[param request_data] 隔离请求。[param callback] 消费者。
func _enqueue(key: String, request_data: Dictionary, callback: Callable) -> void:
	if not _pending.has(key):
		_pending[key] = []
		_requests[key] = request_data
	if callback.is_valid(): _pending[key].append(callback)


## 每帧最多上传一页或构造一毫秒动画帧，后台仅读取和解码 CPU 数据。
## [param _delta] 渲染帧间隔。
func _process(_delta: float) -> void:
	if not _resource_path.is_empty():
		var status := ResourceLoader.load_threaded_get_status(_resource_path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return
		var visual: Dictionary = {}
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var upload_started_at := PerformanceTelemetryScript.begin(&"resource_upload")
			var resource := ResourceLoader.load_threaded_get(_resource_path)
			if resource is Texture2D:
				repository.cache_page(_resource_path, resource)
				visual = {"texture": resource, "origin": Vector2.ZERO, "size": resource.get_size()}
			elif resource is SpriteFrames: visual = {"sprite_frames": resource}
			PerformanceTelemetryScript.end(&"resource_upload", upload_started_at)
		_resource_path = ""
		_complete(visual)
		return
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task): return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _decoded.has("images"):
			_build = repository.begin_animation(_decoded.definition, _decoded.metadata)
		else:
			_complete(repository.finish_frame(_decoded))
			return
	if _build != null:
		var images: Dictionary = _decoded.images
		if not images.is_empty():
			var upload_started_at := PerformanceTelemetryScript.begin(&"resource_upload")
			var page_path: String = images.keys()[0]
			repository.finish_frame({"path": page_path, "image": images[page_path], "origin": Vector2.ZERO})
			PerformanceTelemetryScript.end(&"resource_upload", upload_started_at)
			images.erase(page_path)
			return
		if not repository.advance_animation(_build): return
		var visual := {} if _build.failed else repository.cached_animation(String(_build.definition.logical_id))
		_build = null
		_complete(visual)
		return
	if _requests.is_empty(): return
	_active_key = _requests.keys()[0]
	for key: String in _requests:
		if not _pending[key].is_empty():
			_active_key = key
			break
	var request_data: Dictionary = _requests[_active_key].duplicate(true)
	var path := String(request_data.path)
	if not path.is_empty() and request_data.kind == "frame":
		var cached := repository.finish_frame({"path": path, "origin": Vector2.ZERO})
		if not cached.is_empty():
			_complete(cached)
			return
	if not path.is_empty() and ResourceLoader.exists(path):
		var resource_type := "SpriteFrames" if request_data.kind == "resource" else "Texture2D"
		if ResourceLoader.load_threaded_request(path, resource_type) == OK:
			_resource_path = path
			return
	if request_data.kind == "resource":
		_complete({})
		return
	request_data["metadata"] = repository.cached_metadata(String(request_data.definition.get("logical_id", "")))
	request_data["cached_pages"] = repository.cached_pages()
	_task = WorkerThreadPool.add_task(_decode.bind(request_data), false, "sprite resource")


## 工作线程只处理隔离数据，不访问场景、GPU 或仓储。
## [param request_data] 主线程准备的请求。
func _decode(request_data: Dictionary) -> void:
	if request_data.kind == "animation":
		_decoded = AleSpriteRepository.read_animation_source(request_data)
	else:
		_decoded = AleSpriteRepository.read_frame_source(request_data)
		if not _decoded.is_empty() and not request_data.cached_pages.has(_decoded.path):
			_decoded["image"] = RuntimeTextureLoader.read_image(_decoded.path)


## 主线程释放等待列表后通知消费者，允许回调再次请求资源。
## [param visual] 就绪资源；失败时为空。
func _complete(visual: Dictionary) -> void:
	var callbacks: Array = _pending[_active_key]
	_pending.erase(_active_key)
	_requests.erase(_active_key)
	_decoded = {}
	for callback: Callable in callbacks:
		if callback.is_valid(): callback.call(visual)


## 退出时等待已开始的 CPU 任务结束，防止引用已经释放的队列。
func _exit_tree() -> void:
	if _task >= 0: WorkerThreadPool.wait_for_task_completion(_task)
