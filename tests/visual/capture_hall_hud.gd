extends SceneTree

const MAIN_SCENE := preload("res://scenes/main_hall.tscn")
## 延迟启动大厅 HUD 截图流程，避免在 SceneTree 尚未就绪时捕获。
## Design: 截图夹具通过延迟调用进入需要跨帧等待的异步捕获阶段。
func _initialize() -> void:
	call_deferred("_capture")


## 实例化大厅、稳定相机与玩家状态并保存 HUD 视觉基准截图。
## Design: 连续等待渲染帧以保证布局、贴图导入和最终合成均已完成。
func _capture() -> void:
	var hall := MAIN_SCENE.instantiate()
	root.add_child(hall)
	await process_frame
	await process_frame
	hall.player.position = Vector2(972, 960)
	hall.camera.position = hall.player.position
	hall._sync_player_nodes()
	await process_frame
	await process_frame
	RenderingServer.force_sync()
	var image := root.get_viewport().get_texture().get_image()
	var capture_path := "res://.godot/hall_hud_free_%dx%d.png" % [image.get_width(), image.get_height()]
	var error := image.save_png(capture_path)
	if error != OK:
		push_error("Could not save Free HUD capture: %s" % error_string(error))
		quit(1)
		return
	print("HALL_HUD_CAPTURE_OK: %s" % capture_path)
	quit(0)
