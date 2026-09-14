extends SceneTree

const MAIN_SCENE := preload("res://scenes/main_hall.tscn")
const CAPTURE_PATH := "res://.godot/hall_depth_case.png"
const UPPER_CAPTURE_PATH := "res://.godot/hall_depth_case_upper.png"


## 延迟启动大厅深度关系截图流程，确保 SceneTree 已完成初始化。
## 设计：捕获流程跨越多个渲染帧，因此由延迟调用进入异步阶段。
func _initialize() -> void:
	call_deferred("_capture")


## 实例化大厅、定位到楼梯遮挡测试点并保存视口截图。
## 设计：连续等待渲染帧以确保场景导入、节点同步和 GPU 绘制均已生效。
func _capture() -> void:
	var hall := MAIN_SCENE.instantiate()
	root.add_child(hall)
	await process_frame
	await process_frame
	var error := await _capture_position(hall, Vector2(984, 900), CAPTURE_PATH)
	if error != OK:
		push_error("Could not save lower visual depth case: %s" % error_string(error))
		quit(1)
		return
	error = await _capture_position(hall, Vector2(744, 564), UPPER_CAPTURE_PATH)
	if error != OK:
		push_error("Could not save upper visual depth case: %s" % error_string(error))
		quit(1)
		return
	print("HALL_DEPTH_CAPTURE_OK: %s, %s" % [CAPTURE_PATH, UPPER_CAPTURE_PATH])
	quit(0)


## 执行 `capture_position` 对应的模块操作。
## [param hall] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param output_path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _capture_position(hall: Node, world_position: Vector2, output_path: String) -> Error:
	hall.world_view.player.position = world_position
	hall.world_view.camera.position = hall.world_view.player.position
	hall.player_binding.sync_position(hall.world_view.player.position)
	await process_frame
	await process_frame
	RenderingServer.force_sync()
	var image := root.get_viewport().get_texture().get_image()
	return image.save_png(output_path)
