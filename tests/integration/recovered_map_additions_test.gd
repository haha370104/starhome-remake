extends SceneTree

const MAPS := ["glory_nft_bt_blackroom", "glory_nft_bt_yzzl", "glory_nft_ds_roomsvr3", "glory_nft_sk_yzzl"]
var checks := 0
var failures: Array[String] = []


## 通过正式预载、导航和世界提交检验补充地图包。
func _initialize() -> void:
	call_deferred("_run")


## 逐张加载新增地图并检查已有出口；测试不连接或修改玩家存档。
func _run() -> void:
	root.size = Vector2i(1100, 760)
	var hall: Node2D = load("res://scenes/main_hall.tscn").instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	var directory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/glory_map_directory_v1.json"))
	var loader := ClientMapPreloader.new()
	root.add_child(loader)
	loader.configure(directory.definitions)
	for id: String in MAPS:
		_check(directory.definitions.has(id), "目录包含 " + id)
		_check(loader.preload_map(StringName(id)) == OK, "补充包预载 " + id)
		var prepared: Array = await loader.map_preload_ready
		var bundle: Dictionary = prepared[1]
		var definition: MapDefinition = bundle.definition
		var spawn := definition.spawn_by_id(definition.default_spawn_id)
		var server_map := AuthoritativeMapInstance.new()
		_check(server_map.load_map(directory.definitions[id]).ok, "服务端导航 " + id)
		_check(server_map.navigation.is_walkable(spawn.position), "出生点可达 " + id)
		_check(hall.active_world_controller.commit_bundle(bundle, spawn.position), "世界提交 " + id)
		hall.map_travel.map_committed.emit()
		await process_frame
		await process_frame
		_check(bundle.resources.floor != null and bundle.resources.minimap != null, "场景与缩略图 " + id)
		for transition: MapTransition in definition.enabled_transitions():
			_check(not transition.external_target and directory.definitions.has(String(transition.destination_map_id)), "原有出站目标可解析")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/%s.png" % id)
	loader.queue_free()
	hall.queue_free()
	await process_frame
	print("Recovered maps: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总目录、表现和导航的实际加载结果。
## [param condition] 实际条件。[param message] 失败上下文。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
