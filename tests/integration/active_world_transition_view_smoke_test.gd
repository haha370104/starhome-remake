extends SceneTree

const MainHallScene := preload("res://scenes/main_hall.tscn")

class TestMapPreloader:
	extends Node

	var requested_map_id: StringName = &""

	## 执行 `preload_map` 对应的模块操作。
	## [param map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
	## 返回该函数计算、查询或操作得到的结果。
	func preload_map(map_id: StringName) -> Error:
		requested_map_id = map_id
		return OK


var failures: PackedStringArray = []
var assertions := 0


## 延迟启动测试，使主场景完成初始地图原子提交。
func _initialize() -> void:
	call_deferred("_run")


## 驱动传送表现命中、接近点路线和失败 bundle 隔离组合回归。
func _run() -> void:
	var hall: Node2D = MainHallScene.instantiate()
	root.add_child(hall)
	await process_frame
	await process_frame
	if not hall.has_method("_handle_world_right_click") or hall.active_world_controller == null:
		_fail("主场景未提供活动世界与右键传送接缝")
		_finish(hall)
		return

	var active: Node = hall.active_world_controller
	var view: Node2D = active.transition_view_by_id(&"exit_to_city")
	_expect(view != null, "大厅必须从地图定义生成 exit_to_city 传送视图")
	if view == null:
		_finish(hall)
		return
	_expect(view.position == Vector2(408, 348), "传送表现必须采用数据声明的业务锚点")
	_expect(view.approach_point == Vector2(480, 370), "传送交互必须保留独立的可行走接近点")
	_expect(active.transition_view_at(Vector2(420, 360)) == view, "固定交互矩形内必须能命中传送图标")
	_expect(active.transition_view_at(Vector2(407, 347)) == null, "固定交互矩形外不得命中传送图标")
	await create_timer(0.15).timeout
	_expect(active.transition_view_at(Vector2(420, 360)) == view, "命中区不得随动画当前帧抖动")

	hall.call("_handle_world_right_click", Vector2(420, 360))
	_expect(hall.selected_transition_id == &"exit_to_city", "右键传送图标必须记录具体业务出口")
	_expect(hall.movement_click_effects.frame_count() == 6, "荣耀版右键落点反馈必须保留完整 6 帧")
	_expect(hall.movement_click_effects.active_effect_count() == 1, "右键点击必须立即创建一次落点反馈")
	_expect(
		hall.movement_click_effects.last_presented_position == Vector2(420, 360),
		"落点反馈必须留在实际点击点，不得跟随寻路接近点",
	)
	_expect(not hall.path_points.is_empty(), "命中传送图标必须生成可行路线")
	if not hall.path_points.is_empty():
		_expect(hall.path_points[-1].is_equal_approx(Vector2(480, 370)), "传送路线终点必须是 approach_point")
	_expect(hall.pending_map_transition.is_empty(), "玩家到达前不得提交地图切换")
	await create_timer(0.65).timeout
	_expect(hall.movement_click_effects.active_effect_count() == 0, "落点反馈必须在约 600ms 后自动删除")

	var test_preloader := TestMapPreloader.new()
	hall.add_child(test_preloader)
	hall.map_preloader = test_preloader
	hall.local_player_controller.set_position(Vector2(480, 370), false)
	hall.call("_on_local_player_route_finished")
	_expect(not hall.pending_map_transition.is_empty(), "玩家到达 approach_point 后必须启动现有权威切图管线")
	_expect(
		StringName(hall.pending_map_transition.get("transition_id", &"")) == &"exit_to_city",
		"到达后只能提交命中的 transition_id",
	)
	_expect(test_preloader.requested_map_id == &"yian_harbor_city", "到达后必须预载 transition 定义的目标地图")
	hall.pending_map_transition.clear()
	hall.selected_transition_id = &""

	_test_failed_bundle_isolation(hall, active)
	_test_city_transition_views(active)
	_expect(assertions == 42, "组合回归必须执行完整的 42 条业务断言")
	_finish(hall)


## 执行 `test_failed_bundle_isolation` 对应的模块操作。
## [param hall] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param active] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _test_failed_bundle_isolation(hall: Node2D, active: Node) -> void:
	var old_definition: RefCounted = active.definition
	var old_navigation: RefCounted = active.navigation
	var old_background: Texture2D = hall.map_background.texture
	var old_player_position: Vector2 = hall.player.position
	var old_map_name: String = hall.hud.minimap_dock.map_name_label.text
	var old_camera_limit := Vector2i(hall.camera.limit_right, hall.camera.limit_bottom)
	var old_scene_count: int = active.scene_nodes.size()
	var old_npc_count: int = active.npc_instances.size()
	var old_first_scene: Node2D = active.scene_nodes[0] if old_scene_count > 0 else null

	var bad_bundle: Dictionary = active.prepare_initial_bundle("res://data/maps/yian_harbor_city.json")
	_expect(not bad_bundle.is_empty(), "故障注入前城市 bundle 本身必须完整")
	if bad_bundle.is_empty():
		return
	var bad_manifest: Dictionary = bad_bundle["map_manifest"].duplicate(true)
	var composition: Dictionary = bad_manifest.get("composition", {})
	var layers: Array = composition.get("semantic_layers", [])
	_expect(not layers.is_empty(), "城市 bundle 必须包含可故障注入的语义层")
	if layers.is_empty():
		return
	layers[0]["atlas_region"] = [0, 0, 32]
	bad_bundle["map_manifest"] = bad_manifest
	_expect(not active.commit_bundle(bad_bundle, Vector2(1399, 954)), "任一目标依赖缺失时原子提交必须失败")

	_expect(active.definition == old_definition, "提交失败必须保留旧地图定义")
	_expect(active.navigation == old_navigation, "提交失败必须保留旧导航实例")
	_expect(hall.map_background.texture == old_background, "提交失败必须保留旧背景")
	_expect(hall.player.position == old_player_position, "提交失败必须保留旧玩家位置")
	_expect(hall.hud.minimap_dock.map_name_label.text == old_map_name, "提交失败必须保留旧 HUD 地图名")
	_expect(Vector2i(hall.camera.limit_right, hall.camera.limit_bottom) == old_camera_limit, "提交失败必须保留旧摄像机边界")
	_expect(active.scene_nodes.size() == old_scene_count, "提交失败必须保留旧语义层数量")
	_expect(active.npc_instances.size() == old_npc_count, "提交失败必须保留旧 NPC 集合")
	_expect(old_first_scene == null or is_instance_valid(old_first_scene), "提交失败不得释放旧场景节点")


## 提交城区地图并验证五处出口全部由八方向公共组件生成。
## [param active] 当前活动世界控制器。
func _test_city_transition_views(active: Node) -> void:
	var city_bundle: Dictionary = active.prepare_initial_bundle("res://data/maps/yian_harbor_city.json")
	_expect(not city_bundle.is_empty(), "城区 bundle 必须可加载")
	if city_bundle.is_empty():
		return
	_expect(active.commit_bundle(city_bundle, Vector2(1399, 954)), "城区 bundle 必须可原子提交")
	_expect(active.transition_views.size() == 5, "城区五个已启用出口必须全部显示传送动画")
	var expected_orientations := {
		&"enter_base_hall_floor_1": "north_east",
		&"exit_to_d04_northwest_gate": "north_west",
		&"exit_to_d04_southwest_gate": "south_west",
		&"exit_to_d04_southeast_gate": "south_east",
		&"exit_to_d04_northeast_gate": "north_east",
	}
	for transition_id: StringName in expected_orientations:
		var view: Node2D = active.transition_view_by_id(transition_id)
		_expect(view != null, "城区传送点必须存在：%s" % transition_id)
		if view == null:
			continue
		var sprite := view.get_node_or_null("AnimatedIcon") as AnimatedSprite2D
		var expected_fragment := "/%s/animation_frames.tres" % expected_orientations[transition_id]
		_expect(
			sprite != null and String(sprite.sprite_frames.resource_path).ends_with(expected_fragment),
			"城区传送点必须使用对应方向的共享 as1-as8 动画：%s" % transition_id,
		)


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 执行 `fail` 对应的模块操作。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _fail(message: String) -> void:
	failures.append(message)


## 执行 `finish` 对应的模块操作。
## [param hall] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _finish(hall: Node2D) -> void:
	if failures.is_empty():
		print("ACTIVE_WORLD_TRANSITION_VIEW_OK (%d assertions)" % assertions)
		hall.free()
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	hall.free()
	quit(1)
