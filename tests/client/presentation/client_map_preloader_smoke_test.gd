extends SceneTree

const PreloaderScript := preload("res://scripts/client/presentation/client_map_preloader.gd")

var failures: PackedStringArray = []
var assertions := 0
var ready_bundle: Dictionary = {}
var ready_map_id: StringName = &""
var failed_map_id: StringName = &""


## 延迟运行地图预载测试，使测试节点拥有可处理帧的 SceneTree。
func _initialize() -> void:
	call_deferred("_run")


## 验证未知地图隔离、荣耀版大厅贴图异步预载及原子 bundle 交付。
func _run() -> void:
	var preloader: Node = PreloaderScript.new()
	root.add_child(preloader)
	preloader.map_preload_ready.connect(_on_map_preload_ready)
	preloader.map_preload_failed.connect(_on_map_preload_failed)
	preloader.configure({
		&"yian_harbor_hall_floor_1": "res://data/maps/yian_harbor_hall_floor_1.json",
		&"yian_harbor_city": "res://data/maps/yian_harbor_city.json",
		&"g08_field_zone": "res://data/maps/g08_field_zone.json",
	})

	_expect(preloader.preload_map(&"missing_map") == ERR_DOES_NOT_EXIST, "未知地图必须在预载前失败")
	_expect(failed_map_id == &"missing_map", "未知地图失败事件应保留请求 map_id")
	failed_map_id = &""
	_expect(preloader.preload_map(&"g08_field_zone") == ERR_FILE_NOT_FOUND, "未导入表现资源的地图必须安全失败")
	_expect(failed_map_id == &"g08_field_zone", "表现资源缺失事件应保留请求 map_id")
	failed_map_id = &""
	_expect(preloader.preload_map(&"yian_harbor_hall_floor_1") == OK, "大厅预载应进入线程队列")
	_expect(preloader.is_preloading(), "加载完成前应报告预载中")
	for _frame in range(240):
		if not ready_bundle.is_empty() or not failed_map_id.is_empty():
			break
		await process_frame
	_expect(failed_map_id.is_empty(), "合法地图预载不应失败：%s" % failed_map_id)
	_expect(not ready_bundle.is_empty(), "合法地图应在限定帧内交付完整资源包")
	if not ready_bundle.is_empty():
		_expect(ready_map_id == &"yian_harbor_hall_floor_1", "预载完成事件 map_id 不匹配")
		_expect(ready_bundle["definition"].map_id == &"yian_harbor_hall_floor_1", "资源包地图定义不匹配")
		_expect(ready_bundle["resources"].get("floor") is Texture2D, "资源包必须包含底图纹理")
		_expect(ready_bundle["resources"].get("minimap") is Texture2D, "资源包必须包含小地图纹理")
		_expect(ready_bundle["map_manifest"] is Dictionary, "资源包必须包含已解析场景清单")
	_expect(not preloader.is_preloading(), "原子交付后必须释放暂存状态")
	ready_bundle.clear()
	ready_map_id = &""
	_expect(preloader.preload_map(&"yian_harbor_city") == OK, "城市语义表现应可异步预载")
	for _frame in range(240):
		if not ready_bundle.is_empty() or not failed_map_id.is_empty():
			break
		await process_frame
	_expect(failed_map_id.is_empty(), "城市预载不应失败")
	_expect(ready_map_id == &"yian_harbor_city", "城市预载应交付对应业务 map_id")
	if not ready_bundle.is_empty():
		_expect(ready_bundle["map_manifest"]["composition"]["render_strategy"] == "semantic_owner_layers", "城市必须使用语义遮挡图层")

	if failures.is_empty():
		print("CLIENT_MAP_PRELOADER_SMOKE_OK (%d assertions)" % assertions)
		preloader.free()
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	preloader.free()
	quit(1)


## 保存 [param map_id] 对应的完整 [param bundle] 供主测试断言。
func _on_map_preload_ready(map_id: StringName, bundle: Dictionary) -> void:
	ready_map_id = map_id
	ready_bundle = bundle


## 保存 [param map_id] 的预载失败结果；[param _message] 仅供诊断。
func _on_map_preload_failed(map_id: StringName, _message: String) -> void:
	failed_map_id = map_id


## 累加断言，并在 [param condition] 不成立时记录 [param message]。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
