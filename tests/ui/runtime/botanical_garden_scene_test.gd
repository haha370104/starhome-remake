extends SceneTree

var _fixture := PlayerPanelServiceFixture.new()
var _service := AuthoritativeGardenService.new()
var _hall: Node2D
var checks := 0
var failures: Array[String] = []


## 延迟建立主场景，测试不连接日常会话。
func _initialize() -> void:
	call_deferred("_run")


## 检查地图切换、果实图层、菜单采摘和旧地图回复隔离。
func _run() -> void:
	root.size = Vector2i(1280, 800)
	_check(_fixture.initialize().is_ok and _service.initialize(_fixture._service.item_catalog()).is_ok, "服务夹具")
	_hall = load("res://scenes/main_hall.tscn").instantiate()
	_hall.multiplayer_connect_automatically = false
	root.add_child(_hall)
	await process_frame
	_hall.panel_session._dispatcher = _dispatch
	var active: ActiveWorldController = _hall.active_world_controller
	var preloader := ClientMapPreloader.new()
	root.add_child(preloader)
	preloader.configure({&"glory_nft_bl_treeroom1": "res://content/glory/map_definitions/glory_nft_bl_treeroom1.json"})
	preloader.preload_map(&"glory_nft_bl_treeroom1")
	var prepared: Array = await preloader.map_preload_ready
	var bundle: Dictionary = prepared[1]
	preloader.queue_free()
	_fixture._state.map_id = _service.rules.map_id
	_fixture._state.position = Vector2(1536, 2280)
	_check(active.commit_bundle(bundle, _fixture._state.position), "植物园提交")
	_hall.map_travel.map_committed.emit()
	await process_frame
	var garden: BotanicalGardenController = _hall.interactions.garden
	_check(garden.plants.size() == 15, "15棵果实属于独立控制器")
	if garden.plants.is_empty():
		quit(1)
		return
	var fruit: WorldGardenPlant = garden.plants[0]
	_check(garden.plant_at(fruit.position + fruit._offset) == fruit, "命中果实图片")
	_check(fruit._sprite.visible, "查询后成熟图像显示")
	_hall.interactions.show_npc_popup(fruit)
	_check(_hall.interactions.active_npc == fruit, "共用NPC菜单选中果实")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/botanical_garden.png")
	_hall.hud.npc_action_requested.emit("harvest_garden")
	_check(_fixture._state.garden.remaining(fruit.plant_id, int(Time.get_unix_time_from_system())) > 0, "菜单接到权威采摘")
	_check(not fruit._sprite.visible and _hall.interactions.active_npc == null, "成功后隐藏果实并关闭菜单")
	var old := _service.build_bundle(_fixture._state)
	bundle = active.prepare_initial_bundle("res://data/maps/yian_harbor_hall_floor_1.json")
	_check(active.commit_bundle(bundle, bundle.definition.spawn_by_id(bundle.definition.default_spawn_id).position), "返回大厅")
	_hall.map_travel.map_committed.emit()
	garden.apply_bundle(old)
	_check(garden.plants.is_empty(), "切图清空并拒绝迟到回复")
	_hall.queue_free()
	await process_frame
	print("Garden scene: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 桥接隔离领域服务并发布真正的提交结果。
## [param command] 菜单发出的语义意图。
func _dispatch(command: Dictionary) -> void:
	if command.get("type") not in AuthoritativeGardenService.COMMANDS: return
	var result := _service.execute(_fixture._state, command)
	_check(result.is_ok, "采摘命令通过")
	if not result.is_ok: return
	if result.value.get("changed", false):
		_fixture._state = result.value.candidate
		_fixture._state.revision += 1
	_hall.panel_session.apply_bundle(_service.build_bundle(_fixture._state, result.value.get("operation", {})))


## 汇总场景和交互结果。
## [param condition] 实际状态。[param message] 期望说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
