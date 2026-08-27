class_name ClientMapPreloader
extends Node

signal map_preload_ready(map_id: StringName, bundle: Dictionary)
signal map_preload_failed(map_id: StringName, message: String)

const MapDefinitionLoaderScript := preload("res://scripts/maps/map_definition_loader.gd")

var _definition_paths: Dictionary = {}
var _pending_map_id: StringName = &""
var _pending_definition
var _pending_resource_paths: Dictionary = {}


## 使用 [param definition_paths] 配置业务 map_id 到 `MapDefinition` JSON 的本地映射。
## Design: 该目录由版本化内容包提供，服务端消息不能注入任意客户端文件路径。
func configure(definition_paths: Dictionary) -> void:
	_definition_paths.clear()
	for map_id_value in definition_paths:
		var map_id := StringName(String(map_id_value))
		var definition_path := String(definition_paths[map_id_value])
		if not map_id.is_empty() and definition_path.begins_with("res://"):
			_definition_paths[map_id] = definition_path
	set_process(false)


## 异步预载 [param map_id] 的贴图，并把地图定义与场景清单暂存到同一个原子 bundle。
## Returns 请求进入加载队列返回 `OK`，未知地图、忙碌或配置错误时返回对应错误码。
## Design: 只有全部依赖成功后才发布 `map_preload_ready`，失败不会触碰当前场景。
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
	for resource_key in [&"floor", &"minimap"]:
		var resource_path := String(definition.resource_paths.get(String(resource_key), ""))
		if resource_path.is_empty():
			continue
		var request_error := ResourceLoader.load_threaded_request(resource_path)
		if request_error != OK:
			_fail_pending("无法预载 %s：%s" % [resource_key, error_string(request_error)])
			return request_error
		_pending_resource_paths[resource_key] = resource_path
	if _pending_resource_paths.is_empty():
		call_deferred("_complete_pending")
	else:
		set_process(true)
	return OK


## 放弃当前预载结果；已进入 Godot 资源缓存的底层请求可复用但不会再提交到场景。
func cancel_preload() -> void:
	_clear_pending()


## 查询当前是否正在为某张地图组装原子资源包。
## Returns 尚有未提交的地图请求时返回 `true`。
func is_preloading() -> bool:
	return not _pending_map_id.is_empty()


## 轮询 Godot 线程加载状态，并在所有贴图完成后提交资源包。
## [param _delta] 本帧经过时间；加载状态不依赖其数值。
func _process(_delta: float) -> void:
	if _pending_map_id.is_empty():
		set_process(false)
		return
	for resource_path_value in _pending_resource_paths.values():
		var resource_path := String(resource_path_value)
		var status := ResourceLoader.load_threaded_get_status(resource_path)
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail_pending("资源异步加载失败：%s" % resource_path)
			return
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			return
	_complete_pending()


## 读取非贴图清单、收集线程结果并一次性发布当前地图资源包。
func _complete_pending() -> void:
	if _pending_map_id.is_empty() or _pending_definition == null:
		return
	var bundle := {
		"definition": _pending_definition,
		"map_manifest": {},
		"resources": {},
	}
	for resource_key in _pending_resource_paths:
		var resource_path := String(_pending_resource_paths[resource_key])
		var resource := ResourceLoader.load_threaded_get(resource_path)
		if resource == null:
			_fail_pending("资源加载结果为空：%s" % resource_path)
			return
		bundle["resources"][String(resource_key)] = resource
	var manifest_path := String(_pending_definition.resource_paths.get("scene_manifest", ""))
	if not manifest_path.is_empty():
		if not FileAccess.file_exists(manifest_path):
			_fail_pending("场景清单不存在：%s" % manifest_path)
			return
		var parsed_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not parsed_manifest is Dictionary:
			_fail_pending("场景清单格式无效：%s" % manifest_path)
			return
		bundle["map_manifest"] = parsed_manifest
	var completed_map_id := _pending_map_id
	_clear_pending()
	map_preload_ready.emit(completed_map_id, bundle)


## 以 [param message] 结束当前请求并发布失败事件。
func _fail_pending(message: String) -> void:
	var failed_map_id := _pending_map_id
	_clear_pending()
	map_preload_failed.emit(failed_map_id, message)


## 清空所有暂存引用并停止逐帧轮询。
func _clear_pending() -> void:
	_pending_map_id = &""
	_pending_definition = null
	_pending_resource_paths.clear()
	set_process(false)
