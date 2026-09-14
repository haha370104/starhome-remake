extends SceneTree

const MainHallScene := preload("res://scenes/main_hall.tscn")

class MovementIntentProbe:
	extends Node
	var targets: Array[Vector2] = []

	## 记录移动服务真正发布的网络意图，证明 UI 没有直接修改角色位置。
	## [param position] 已经完成可达性处理的终点。
	## 返回独立预测输入序号。
	func request_move(position: Vector2) -> Dictionary:
		targets.append(position)
		return {"input_sequence": targets.size()}

	## 接收本地预测位移，测试只验证意图和场景路线。
	## [param _sequence] 输入序号。
	## [param _displacement] 本帧位移。
	func record_local_predicted_delta(_sequence: int, _displacement: Vector2) -> void:
		pass

	## 接收路线完成通知，允许移动控制器继续触发出口检查。
	## [param _sequence] 已完成的输入序号。
	func finish_local_predicted_route(_sequence: int) -> void:
		pass

class PreloadProbe:
	extends ClientMapPreloader
	var requested_map: StringName

	## 捕获到达出口后的既有切图请求，避免测试访问外部服务。
	## [param map_id] 要预载的目标地图。
	## 返回预载请求已接收。
	func preload_map(map_id: StringName) -> Error:
		requested_map = map_id
		return OK

var checks := 0
var failures: Array[String] = []


## 等待主场景与 HUD 完成初始地图提交。
func _initialize() -> void:
	call_deferred("_run")


## 验证真实地图的点选寻路、巡逻目标重解析、到达出口及原子地图替换。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var hall: Node2D = MainHallScene.instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	await process_frame
	var active: ActiveWorldController = hall.active_world_controller
	var movement: LocalPlayerController = hall.local_player_controller
	var panel: MapNavigationPanel = hall.hud.map_navigation_panel
	var intent := MovementIntentProbe.new()
	hall.add_child(intent)
	movement.set_multiplayer_presenter(intent)
	_expect(panel.listing.points.size() == active.npc_instances.size() + active.facility_instances.size()
		+ active.definition.enabled_transitions().size(), "列表包括当前所有 NPC、设施和启用出口")
	var original_position := movement.position()
	hall.hud.map_navigation_requested.emit(Vector2(900, 1300), &"")
	_expect(not movement.path_points.is_empty() and intent.targets.size() == 1, "坐标导航经过唯一寻路及移动意图流程")
	_expect(movement.position() == original_position, "点击只创建路线，不瞬移玩家")
	_expect(active.navigation.is_walkable(movement.path_points[-1]), "目标经过既有可达性校验")
	movement.cancel_route()
	var npc: Node2D = active.npc_instances[0]
	var old_point: MapNavigationPoint = active.navigation_points()[0]
	npc.position = active.navigation.closest_reachable_position(original_position, Vector2(1100, 1200))
	hall.hud.map_navigation_requested.emit(old_point.destination, old_point.id)
	_expect(intent.targets.back().is_equal_approx(npc.position), "点击巡逻 NPC 时重新解析实时坐标，忽略旧快照")
	active.refresh_navigation_points()
	_expect((panel.listing.rows[0].get_node("Coordinates") as Label).text.contains("%d, %d" % [npc.position.x, npc.position.y]), "巡逻坐标刷新到侧栏")
	var count := intent.targets.size()
	hall.hud.map_navigation_requested.emit(Vector2(100, 100), &"NPC:removed")
	_expect(intent.targets.size() == count, "失效目的地不得回退成旧坐标导航")
	hall.hud.map_navigation_requested.emit(Vector2.INF, &"")
	hall.hud.map_navigation_requested.emit(Vector2(-1, 50), &"")
	_expect(intent.targets.size() == count, "拒绝非法和地图外坐标")
	hall.map_travel.pending_map_transition = {"transition_id": &"exit_to_city"}
	hall.hud.map_navigation_requested.emit(Vector2(900, 1300), &"")
	_expect(intent.targets.size() == count and not movement.has_active_route(), "切图锁定时不能通过地图发出移动")
	hall.map_travel.pending_map_transition.clear()
	movement.set_movement_enabled(false)
	hall.hud.map_navigation_requested.emit(Vector2(900, 1300), &"")
	_expect(intent.targets.size() == count, "地图导航遵守无推进器限制")
	movement.set_movement_enabled(true)
	var index := -1
	for i in panel._points.size():
		if panel._points[i].transition_id == &"exit_to_city":
			index = i
	_expect(index >= 0, "大厅列表包含通向龙之城的出口")
	panel.listing.rows[index].pressed.emit()
	_expect(hall.map_travel.selected_transition_id == &"exit_to_city", "列表选择保留精确出口标识")
	_expect(movement.path_points[-1].is_equal_approx(Vector2(480, 370)), "传送路线前往可达入口而非图片锚点")
	var preloader := PreloadProbe.new()
	hall.add_child(preloader)
	hall.map_travel.map_preloader = preloader
	for step in 200:
		if not movement.has_active_route():
			break
		movement.advance(1.0)
	_expect(movement.position().is_equal_approx(Vector2(480, 370)), "既有移动控制器沿路线走到出口")
	_expect(preloader.requested_map == &"yian_harbor_city", "到达地图面板选择的出口自动进入原切图流程")
	hall.map_travel.pending_map_transition.clear()
	var bundle: Dictionary = active.prepare_initial_bundle("res://data/maps/yian_harbor_city.json")
	panel.show()
	_expect(active.commit_bundle(bundle, Vector2(1399, 954)), "城市地图完整提交")
	_expect(panel.visible and panel.canvas.world_size == active.map_size, "开着面板切图，底图尺寸同步更换")
	_expect(panel.listing.points.size() == active.navigation_points().size(), "新列表与新地图实体严格一致")
	_expect(panel._points.all(func(point: MapNavigationPoint) -> bool:
		return point.transition_id != &"exit_to_city"), "旧地图传送点全部清除")
	_expect(panel.canvas.player_position == movement.position(), "切图后玩家标记同步新落点")
	if "--capture-map-navigation" in OS.get_cmdline_user_args():
		panel.position = Vector2(190, 95)
		panel.show()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/map_navigation_city.png")
	_test_transition_projection()
	hall.free()
	for failure in failures:
		push_error(failure)
	print("MAP_NAVIGATION_SCENE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 同址多目的地仍是不同列表项，禁用出口不应暴露为可选目标。
func _test_transition_projection() -> void:
	var first := MapTransition.new()
	first.transition_id = &"first"
	first.label = "一号入口"
	first.source_anchor = Vector2(100, 100)
	first.approach_point = Vector2(120, 140)
	var second := MapTransition.new()
	second.transition_id = &"second"
	second.source_anchor = first.source_anchor
	var disabled := MapTransition.new()
	disabled.enabled = false
	var points := MapNavigationPoint.collect([], [], [first, second, disabled])
	_expect(points.size() == 2 and points[0].id != points[1].id, "同址多目的地独立选择，过滤禁用传送点")
	_expect(points[0].position != points[0].destination, "展示坐标和寻路入口保持独立")


## 累积完整场景断言，退出前统一报告失败。
## [param condition] 预期条件。
## [param message] 失败时的业务说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
