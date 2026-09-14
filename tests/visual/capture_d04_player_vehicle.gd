extends SceneTree

const MAIN_SCENE := preload("res://scenes/main_hall.tscn")
const D04_DEFINITION := "res://data/maps/d04_field_zone.json"
const CAPTURE_PATH := "res://.godot/d04_player_vehicle.png"


## 延迟启动真实 D04 bundle 与 GPU 截图流程。
func _initialize() -> void:
	call_deferred("_capture")


## 提交城区入口对应的 D04 出生点，并捕获八向新兵战车实景。
func _capture() -> void:
	var hall: Node2D = MAIN_SCENE.instantiate()
	root.add_child(hall)
	await process_frame
	await process_frame
	var bundle: Dictionary = hall.active_world_controller.prepare_initial_bundle(D04_DEFINITION)
	if bundle.is_empty():
		push_error("Could not prepare D04 bundle")
		quit(1)
		return
	var definition: MapDefinition = bundle["definition"]
	var spawn: MapSpawnPoint = definition.spawn_for_entry(1)
	if spawn == null or not hall.active_world_controller.commit_bundle(bundle, spawn.position):
		push_error("Could not commit D04 bundle")
		quit(1)
		return
	hall.world_view.player.set_action("stand", 7)
	hall.world_view.camera.position = spawn.position
	hall.world_view.camera.reset_smoothing()
	hall.player_binding.sync_position(hall.world_view.player.position)
	await process_frame
	await process_frame
	RenderingServer.force_sync()
	var image := root.get_viewport().get_texture().get_image()
	var save_error := image.save_png(CAPTURE_PATH)
	if save_error != OK:
		push_error("Could not save D04 player vehicle capture: %s" % error_string(save_error))
		quit(1)
		return
	print("D04_PLAYER_VEHICLE_CAPTURE_OK: %s" % CAPTURE_PATH)
	quit(0)
