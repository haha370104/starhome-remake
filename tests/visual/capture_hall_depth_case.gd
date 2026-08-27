extends SceneTree

const MAIN_SCENE := preload("res://scenes/main_hall.tscn")
const CAPTURE_PATH := "res://.godot/hall_depth_case.png"
const UPPER_CAPTURE_PATH := "res://.godot/hall_depth_case_upper.png"


## 延迟启动大厅深度关系截图流程，确保 SceneTree 已完成初始化。
## Design: 捕获流程跨越多个渲染帧，因此由延迟调用进入异步阶段。
func _initialize() -> void:
	call_deferred("_capture")


## 实例化大厅、定位到楼梯遮挡测试点并保存视口截图。
## Design: 连续等待渲染帧以确保场景导入、节点同步和 GPU 绘制均已生效。
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


## Captures one real-player occlusion case at the supplied world foot point.
## [param hall] is the live production hall instance.
## [param world_position] is the dynamic character Y-sort position.
## [param output_path] receives the GPU-rendered PNG and its save status.
## Returns the PNG encoder status for this capture point.
func _capture_position(hall: Node, world_position: Vector2, output_path: String) -> Error:
	hall.player.position = world_position
	hall.camera.position = hall.player.position
	hall._sync_player_nodes()
	await process_frame
	await process_frame
	RenderingServer.force_sync()
	var image := root.get_viewport().get_texture().get_image()
	return image.save_png(output_path)
