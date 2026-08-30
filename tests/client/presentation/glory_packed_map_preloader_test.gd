extends SceneTree

const BootstrapScript := preload("res://scripts/content/runtime_content_bootstrap.gd")
const PreloaderScript := preload("res://scripts/client/presentation/client_map_preloader.gd")
const DIRECTORY_PATH := "res://data/maps/glory_map_directory_v1.json"

var failures: PackedStringArray = []
var assertions := 0
var ready_bundle: Dictionary = {}
var failure_message := ""


## 执行本测试脚本的全部验证并汇总结果。
func _initialize() -> void:
	call_deferred("_run")


## 执行 `run` 对应的模块操作。
func _run() -> void:
	var mount_result: Dictionary = BootstrapScript.mount_default()
	_expect(bool(mount_result.get("ok", false)), String(mount_result.get("message", "")))
	_expect(BootstrapScript.is_mounted(), "内容引导器应报告已挂载")
	var directory: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY_PATH))
	_expect(directory is Dictionary, "全量地图目录必须可读")
	if not directory is Dictionary:
		_finish()
		return
	var preloader: Node = PreloaderScript.new()
	root.add_child(preloader)
	preloader.map_preload_ready.connect(func(_map_id, bundle): ready_bundle = bundle)
	preloader.map_preload_failed.connect(func(_map_id, message): failure_message = message)
	preloader.configure(directory["definitions"])
	_expect(preloader.preload_map(&"glory_nft_bl_2armshop1") == OK, "兵工厂应进入预载")
	for _frame in range(120):
		if not ready_bundle.is_empty() or not failure_message.is_empty():
			break
		await process_frame
	_expect(failure_message.is_empty(), "包内地图预载不应失败：%s" % failure_message)
	_expect(not ready_bundle.is_empty(), "包内地图应在限定帧内完成")
	if not ready_bundle.is_empty():
		_expect(ready_bundle["definition"].map_id == &"glory_nft_bl_2armshop1", "地图定义不匹配")
		_expect(ready_bundle["resources"]["floor"] is Texture2D, "地图底图必须解码为贴图")
		_expect(ready_bundle["resources"]["minimap"] is Texture2D, "小地图必须解码为贴图")
		_expect(
			ready_bundle["map_manifest"]["composition"]["render_strategy"]
				== "flattened_source_composite",
			"批量导入地图必须明确标记平面合成策略",
		)
	ready_bundle.clear()
	failure_message = ""
	_expect(preloader.preload_map(&"buli_c04_field_zone") == OK, "D04 相邻的 C04 应进入预载")
	for _frame in range(120):
		if not ready_bundle.is_empty() or not failure_message.is_empty():
			break
		await process_frame
	_expect(failure_message.is_empty(), "C04 运行资源不应缺失：%s" % failure_message)
	_expect(not ready_bundle.is_empty(), "C04 应在限定帧内交付完整资源包")
	if not ready_bundle.is_empty():
		_expect(ready_bundle["definition"].map_id == &"buli_c04_field_zone", "C04 地图定义不匹配")
		_expect(ready_bundle["resources"]["floor"] is Texture2D, "C04 必须交付地图底图")
	preloader.free()
	_finish()


## 汇总测试断言并以对应退出码结束测试。
func _finish() -> void:
	if failures.is_empty():
		print("GLORY_PACKED_MAP_PRELOADER_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 记录一项测试断言及其失败信息。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
