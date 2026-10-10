class_name ClientMapPreloader
extends Node

signal map_preload_ready(map_id: StringName, bundle: Dictionary)
signal map_preload_failed(map_id: StringName, message: String)

const MapDefinitionLoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")
const TEXTURE_CACHE_BYTES := 256 * 1024 * 1024

var _definition_paths: Dictionary = {}
var _pending_map_id: StringName = &""
var _pending_definition
var _pending_resource_paths: Dictionary = {}
var _pending_resources: Dictionary = {}
var _pending_manifest: Dictionary = {}
var _requests: Dictionary = {}
var _texture_cache: Dictionary = {}
var _evicted_texture_paths: Dictionary = {}
var _cached_bytes := 0
var _cache_clock := 0
var _active_map_id: StringName = &""
var _active_resource_paths: Dictionary = {}


## 执行 `configure` 对应的模块操作。
## [param definition_paths] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该目录由版本化内容包提供，服务端消息不能注入任意客户端文件路径。
func configure(definition_paths: Dictionary) -> void:
	_clear_pending()
	_definition_paths.clear()
	for map_id_value in definition_paths:
		var map_id := StringName(String(map_id_value))
		var definition_path := String(definition_paths[map_id_value])
		if not map_id.is_empty() and definition_path.begins_with("res://"):
			_definition_paths[map_id] = definition_path


## 执行 `preload_map` 对应的模块操作。
## [param map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：只有全部依赖成功后才发布 `map_preload_ready`，失败不会触碰当前场景。
func preload_map(map_id: StringName) -> Error:
	if not _pending_map_id.is_empty():
		return ERR_BUSY
	var definition_path := String(_definition_paths.get(map_id, ""))
	if definition_path.is_empty():
		map_preload_failed.emit(map_id, "客户端内容包不包含地图：%s" % map_id)
		return ERR_DOES_NOT_EXIST
	var loader := MapDefinitionLoaderScript.new()
	var definition = loader.load_file(definition_path)
	if definition == null:
		map_preload_failed.emit(map_id, "; ".join(loader.errors))
		return ERR_FILE_CORRUPT
	if definition.map_id != map_id:
		map_preload_failed.emit(map_id, "地图目录与定义 map_id 不一致")
		return ERR_INVALID_DATA
	for required_key in [&"floor", &"minimap", &"scene_manifest"]:
		var required_path := String(definition.resource_paths.get(String(required_key), ""))
		if required_path.is_empty() or not FileAccess.file_exists(required_path):
			map_preload_failed.emit(
				map_id,
				"地图表现资源尚未导入：%s" % required_key,
			)
			return ERR_FILE_NOT_FOUND

	_pending_map_id = map_id
	_pending_definition = definition
	_pending_resource_paths.clear()
	_pending_resources.clear()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(definition.resource_paths.scene_manifest))
	if not manifest is Dictionary:
		_fail_pending("场景清单格式无效")
		return ERR_FILE_CORRUPT
	_pending_manifest = manifest
	var paths := texture_paths(definition, _pending_manifest)
	for resource_key: String in paths:
		var resource_path: String = paths[resource_key]
		if _texture_cache.has(resource_path):
			_touch_texture(resource_path)
			PerformanceTelemetryScript.increment(&"map_resource_cache_hits")
			_pending_resources[resource_key] = _texture_cache[resource_path].texture
			continue
		PerformanceTelemetryScript.increment(&"map_resource_cache_misses")
		if _evicted_texture_paths.has(resource_path):
			PerformanceTelemetryScript.increment(&"map_resource_cache_reloads")
			_evicted_texture_paths.erase(resource_path)
		if not ResourceLoader.exists(resource_path):
			_fail_pending("地图贴图尚未完成 Godot 导入：%s" % resource_path)
			return ERR_FILE_NOT_FOUND
		if not _requests.has(resource_path):
			var request_error := ResourceLoader.load_threaded_request(resource_path)
			if request_error != OK:
				_fail_pending("无法预载 %s：%s" % [resource_key, error_string(request_error)])
				return request_error
			_requests[resource_path] = true
		_pending_resource_paths[resource_key] = resource_path
	set_process(true)
	return OK


## 收集地图底图、小地图和独立场景图层，供启动加载及异步预载共用。
## [param definition] 地图定义。[param manifest] 场景清单。
## 返回资源键到纹理路径的映射；场景纹理以路径为键去重。
static func texture_paths(definition: MapDefinition, manifest: Dictionary) -> Dictionary:
	var paths := {"floor": String(definition.resource_paths.floor), "minimap": String(definition.resource_paths.minimap)}
	var composition: Dictionary = manifest.get("composition", {})
	var rows: Array = composition.get("semantic_layers", []) if composition.get("render_strategy") in ["semantic_owner_layers", "semantic_foreground_overlay"] else composition.get("props", [])
	for row: Dictionary in rows:
		var path := String(row.get("texture", ""))
		paths[path] = path
	return paths


## 放弃当前预载结果；已进入 Godot 资源缓存的底层请求可复用但不会再提交到场景。
func cancel_preload() -> void:
	_clear_pending()


## 查询当前是否正在为某张地图组装原子资源包。
## 返回该函数计算、查询或操作得到的结果。
func is_preloading() -> bool:
	return not _pending_map_id.is_empty()


func activate_map(map_id: StringName, bundle: Dictionary) -> void:
	_active_map_id = map_id
	_active_resource_paths.clear()
	var definition: MapDefinition = bundle.get("definition")
	var manifest: Dictionary = bundle.get("map_manifest", {})
	for path: String in texture_paths(definition, manifest).values():
		_active_resource_paths[path] = true
		_touch_texture(path)
	_evict_texture_cache()


func deactivate_map() -> void:
	_active_map_id = &""
	_active_resource_paths.clear()
	_evict_texture_cache()


## 轮询 Godot 线程加载状态，并在所有贴图完成后提交资源包。
## [param _delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _process(_delta: float) -> void:
	for resource_path: String in _requests.keys():
		var status := ResourceLoader.load_threaded_get_status(resource_path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var resource := ResourceLoader.load_threaded_get(resource_path)
		_requests.erase(resource_path)
		for key: String in _pending_resource_paths.keys():
			if _pending_resource_paths[key] != resource_path: continue
			if not resource is Texture2D:
				_fail_pending("资源异步加载失败：%s" % resource_path)
				break
			_pending_resources[key] = resource
			_pending_resource_paths.erase(key)
	if not _pending_map_id.is_empty() and _pending_resource_paths.is_empty():
		_complete_pending()
	set_process(not _pending_map_id.is_empty() or not _requests.is_empty())


## 缓存已完成的纹理并一次性发布当前地图资源包。
func _complete_pending() -> void:
	if _pending_map_id.is_empty() or _pending_definition == null:
		return
	var bundle := {
		"definition": _pending_definition,
		"map_manifest": _pending_manifest,
		"resources": _pending_resources.duplicate(),
	}
	var paths := texture_paths(_pending_definition, _pending_manifest)
	for key: String in paths:
		_retain_texture(paths[key], bundle.resources[key])
	var completed_map_id := _pending_map_id
	_clear_pending()
	map_preload_ready.emit(completed_map_id, bundle)


## 按最近使用顺序保留纹理；预算仅约束额外缓存，不强制释放活动地图资源。
## [param path] 纹理路径。[param texture] 已在线程完成加载的纹理。
func _retain_texture(path: String, texture: Texture2D) -> void:
	var previous: Dictionary = _texture_cache.get(path, {})
	_cached_bytes -= int(previous.get("bytes", 0))
	_texture_cache.erase(path)
	# 按 RGBA8 加完整 mip 链估算上限，压缩纹理也使用此保守预算。
	var bytes := ceili(texture.get_width() * texture.get_height() * 16.0 / 3.0)
	_cache_clock += 1
	_texture_cache[path] = {"texture": texture, "bytes": bytes, "last_used": _cache_clock}
	_cached_bytes += bytes
	_evict_texture_cache()


func _touch_texture(path: String) -> void:
	if not _texture_cache.has(path):
		return
	_cache_clock += 1
	_texture_cache[path].last_used = _cache_clock


func _evict_texture_cache() -> void:
	while _cached_bytes > TEXTURE_CACHE_BYTES:
		var oldest := ""
		var oldest_tick := INF
		for path: String in _texture_cache:
			if _active_resource_paths.has(path):
				continue
			var last_used := int(_texture_cache[path].get("last_used", 0))
			if last_used < oldest_tick:
				oldest_tick = last_used
				oldest = path
		if oldest.is_empty():
			break
		_cached_bytes -= int(_texture_cache[oldest].get("bytes", 0))
		_texture_cache.erase(oldest)
		_evicted_texture_paths[oldest] = true
		PerformanceTelemetryScript.increment(&"map_resource_cache_evictions")
	PerformanceTelemetryScript.set_gauge(&"map_resource_cache_bytes", _cached_bytes)
	PerformanceTelemetryScript.set_gauge(&"map_resource_cache_entries", _texture_cache.size())


## 执行 `fail_pending` 对应的模块操作。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _fail_pending(message: String) -> void:
	var failed_map_id := _pending_map_id
	_clear_pending()
	map_preload_failed.emit(failed_map_id, message)


## 清空当前请求；已启动的线程继续回收结果，但不发布被取消的地图。
func _clear_pending() -> void:
	_pending_map_id = &""
	_pending_definition = null
	_pending_resource_paths.clear()
	_pending_resources.clear()
	_pending_manifest = {}
	set_process(not _requests.is_empty())
