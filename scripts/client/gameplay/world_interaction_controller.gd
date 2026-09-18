class_name WorldInteractionController
extends Node

const CombatActions := preload("res://scripts/client/gameplay/client_combat_actions.gd")
var active_npc: Node2D
var transition_choice_ids: Dictionary[String, StringName] = {}
var world_view: ClientWorldView
var active_world_controller: ActiveWorldController
var local_player_controller: LocalPlayerController
var hud: HallHud
var map_travel: MapTravelController
var combat: CombatInteractionController
var game_window_manager: GameWindowManager
var smart_assistant: SmartAssistantController
var death_journal: PveDeathJournalController
var hotkeys := ClientHotkeys.new()


## 在会话启动前绑定窗口与被动日志；未开启智脑也会记录权威击毁。
## [param manager] 已配置共享玩家会话的窗口管理器。
func bind_player_windows(manager: GameWindowManager) -> void:
	game_window_manager = manager
	death_journal = PveDeathJournalController.new()
	add_child(death_journal)
	death_journal.configure(combat.multiplayer_presenter, manager.panel_session,
		active_world_controller, manager.navigation_windows["pve_death_journal"])


## 初始化时暂停输入，直到启动依赖全部配置完毕。
func _init() -> void:
	set_process_unhandled_input(false)


## 连接命中选择、移动、交互菜单所需的依赖；不保存角色或玩法状态。
## [param view] 当前世界视图和鼠标坐标来源。
## [param world] 活动地图与可交互实体的所有者。
## [param movement] 本地移动控制器。
## [param display] 菜单和状态提示接口。
## [param travel] 出口选择与权威切图流程。
## [param battle] 战斗输入与击毁状态入口。
func configure(
	view: ClientWorldView,
	world: ActiveWorldController,
	movement: LocalPlayerController,
	display: HallHud,
	travel: MapTravelController,
	battle: CombatInteractionController,
) -> void:
	world_view = view
	active_world_controller = world
	local_player_controller = movement
	hud = display
	map_travel = travel
	combat = battle
	hud.map_navigation_requested.connect(navigate_from_map)
	set_process_unhandled_input(true)


## 接收并分发当前节点负责的输入事件。
## [param event] 视口中尚未被 GUI 消费的键鼠输入。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit: return
		if hotkeys.matches("self_repair", event):
			combat.request_self_repair()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if combat.is_input_locked():
		get_viewport().set_input_as_handled()
		return
	var mouse_event := event as InputEventMouseButton
	var world_position := world_view.get_global_mouse_position()
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		handle_world_right_click(world_position)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		var npc := nearest_npc(world_position, 55.0)
		if npc:
			show_npc_popup(npc)
		elif world_view.player != null and world_view.player.is_combat_actor_active():
			combat.handle_world_combat_left_click(world_position)
		else:
			hud.hide_popup()
		get_viewport().set_input_as_handled()


## 显示点击反馈，并选择传送接近点、多目标菜单或普通移动。
## [param world_position] 鼠标命中的地图世界坐标。
## 设计：先在实际点击点播放原版反馈；图标锚点仅用于命中，不能替代可行走接近点。
func handle_world_right_click(world_position: Vector2) -> void:
	world_view.movement_click_effects.present(world_position)
	var transition_view: Node2D = active_world_controller.transition_view_at(world_position)
	if transition_view != null:
		var transition: MapTransition = active_world_controller.definition.transition_by_id(transition_view.transition_id)
		if transition != null and transition.kind == MapTransition.Kind.MULTI_CHOICE:
			show_transition_choices(transition, world_position)
			return
		move_to(transition_view.approach_point, transition_view.transition_id)
	else:
		move_to(world_position)


## 向移动控制器请求路径，记录选中出口并呈现不可达原因。
## [param world_position] 鼠标命中的地图世界坐标。
## [param transition_id] 明确选择的出口；空值表示普通移动。
func move_to(world_position: Vector2, transition_id: StringName = &"") -> void:
	if combat.is_input_locked():
		map_travel.stop_moving("地图切换中，暂时不能移动")
		return
	map_travel.selected_transition_id = &""
	var target_text := "%d, %d" % [roundi(world_position.x), roundi(world_position.y)]
	var result: Dictionary = local_player_controller.request_move(world_position)
	if not bool(result.get("ok", false)):
		var error_code := StringName(result.get("code", &""))
		if error_code == &"movement.no_propulsion":
			var error_message := PlayerErrorMessages.describe(error_code)
			hud.show_status(error_message)
			hud.show_system_message(error_message)
		elif error_code == &"no_reachable_point":
			hud.show_status("目标 %s 不可到达，附近也没有可达点" % target_text)
		else:
			hud.show_status("无法找到前往 %s 的路径" % target_text)
		return
	var resolved_position: Vector2 = result["resolved_position"]
	map_travel.selected_transition_id = transition_id
	if bool(result["used_nearest_walkable"]):
		hud.show_status("目标 %s 不可到达，正在前往附近 %d, %d" % [
			target_text,
			roundi(resolved_position.x),
			roundi(resolved_position.y),
		])
	else:
		hud.show_status("正在前往 %s" % target_text)
	hud.hide_popup()


## 查找鼠标点命中的最近 NPC 或生产设施。
## [param world_position] 鼠标对应的地图世界坐标。
## [param maximum_distance] NPC 默认点选距离；设施使用各自配置的命中半径。
## 返回最近的可交互节点；没有命中时返回 null。
func nearest_npc(world_position: Vector2, maximum_distance: float) -> Node2D:
	var result: Node2D
	var closest_distance := INF
	for npc in active_world_controller.npc_instances:
		var distance := npc.position.distance_to(world_position)
		if distance <= maximum_distance and distance < closest_distance:
			closest_distance = distance
			result = npc
	for facility in active_world_controller.facility_instances:
		var distance := facility.position.distance_to(world_position)
		if facility.hit_test(world_position) and distance < closest_distance:
			closest_distance = distance
			result = facility
	return result


## 暂停移动，选中交互实体并将菜单定位到屏幕坐标。
## [param npc] 当前鼠标选择的 NPC 或生产设施视图。
func show_npc_popup(npc: Node2D) -> void:
	map_travel.stop_moving("正在与%s交互" % String(npc.get_interaction_data()["title"]))
	if active_npc and active_npc != npc:
		active_npc.set_interaction_active(false)
	active_npc = npc
	active_npc.set_interaction_active(true)
	var screen_position := get_viewport().get_canvas_transform() * active_npc.global_position
	hud.show_npc_popup(active_npc.get_interaction_data(), screen_position)


## 解除当前实体的交互表现并清空选择。
func on_npc_popup_closed() -> void:
	if active_npc:
		active_npc.set_interaction_active(false)
		active_npc = null


## 将交互菜单动作分派到传送、制造、商店或 NPC 业务处理器。
## [param action_id] 当前菜单发出的业务动作标识。
## 设计：关闭菜单会同步清空 active_npc，窗口所需的标识和标题必须在关闭前读取。
func on_npc_action_requested(action_id: String) -> void:
	if transition_choice_ids.has(action_id):
		var transition_id := StringName(transition_choice_ids[action_id])
		var transition: MapTransition = active_world_controller.definition.transition_by_id(transition_id)
		transition_choice_ids.clear()
		hud.hide_popup()
		if transition != null:
			move_to(transition.approach_point, transition.transition_id)
		return
	if is_instance_valid(active_npc):
		var interaction_title := String(active_npc.get_interaction_data()["title"])
		if action_id == "manufacture" and active_npc is WorldFacilityInteraction:
			var station_id := (active_npc as WorldFacilityInteraction).station_id
			if station_id.is_empty():
				return
			hud.hide_popup()
			game_window_manager.open_manufacturing(station_id)
			hud.show_status("正在使用%s" % interaction_title)
			return
		var npc_id := String(active_npc.get("npc_id"))
		var npc_definition: Variant = active_npc.get("npc_definition")
		var interaction_service := String(npc_definition.get("interaction_service", "")) \
			if npc_definition is Dictionary else ""
		if interaction_service == "commerce" \
				and action_id in ["buy", "sell", "task"]:
			hud.hide_popup()
			game_window_manager.open_weapon_merchant(action_id, npc_id)
			hud.show_status("正在与%s交互" % interaction_title)
			return
		hud.show_status(active_npc.handle_action(action_id))


## 显示同一原版 transport2 锚点的目标选择菜单。
## [param selected] 鼠标命中的任一多目标传送定义。
## [param world_position] 右键点击的地图世界坐标。
## 设计：选择只决定 transition_id；寻路、预载和最终切图仍走既有权威传送链。
func show_transition_choices(selected: MapTransition, world_position: Vector2) -> void:
	transition_choice_ids.clear()
	var actions: Array[Dictionary] = []
	for transition: MapTransition in active_world_controller.definition.enabled_transitions():
		if transition.kind != MapTransition.Kind.MULTI_CHOICE \
				or not transition.source_anchor.is_equal_approx(selected.source_anchor):
			continue
		var action_id := "transition_%s" % String(transition.transition_id)
		transition_choice_ids[action_id] = transition.transition_id
		actions.append({"id": action_id, "label": transition.label})
	var screen_position := get_viewport().get_canvas_transform() * world_position
	hud.show_npc_popup({
		"title": "选择目的地",
		"body": "",
		"actions": actions,
	}, screen_position)


## 将底栏导航交给窗口管理器；好友功能未开放时显示屏幕中央提示。
## [param action_id] 免费版底栏发出的业务动作标识。
func on_hud_action_requested(action_id: String) -> void:
	if action_id == "friends":
		hud.show_system_message("好友列表暂未实现")
		return
	if action_id == "return_base":
		combat.request_vehicle_recovery()
		return
	if action_id == CombatActions.SELF_REPAIR_ABILITY_ID:
		combat.request_self_repair()
		return
	if action_id == "smart_assistant" and smart_assistant == null:
		smart_assistant = SmartAssistantController.new()
		add_child(smart_assistant)
		smart_assistant.configure(combat, game_window_manager.navigation_windows["smart_assistant"])
	if action_id in ["party", "summon_guard"]:
		hud.show_system_message({"party": "队伍功能暂未开放", "summon_guard": "召唤守卫暂未开放"}[action_id])
		return
	if game_window_manager != null and game_window_manager.toggle(action_id):
		return


## 在活动世界原子替换前结束旧 NPC 交互，并清除仅属于旧地图的传送选择。
func clear_interaction() -> void:
	if active_npc and is_instance_valid(active_npc):
		active_npc.set_interaction_active(false)
	active_npc = null
	map_travel.selected_transition_id = &""
	transition_choice_ids.clear()


## 在路线中断后清理出口选择并显示移动控制器的原因。
## [param message] 当前流程产生的失败或状态说明。
func on_local_player_route_stopped(message: String) -> void:
	map_travel.selected_transition_id = &""
	if hud:
		hud.show_status(message)


## 接收地图导航意图，重新解析实时目的地后进入唯一移动流程。
## [param world_position] 普通地图点击的世界坐标。
## [param point_id] 列表目的地的稳定标识；空值表示普通坐标导航。
## 设计：旧地图失效标识不移动；切图、击毁、推进力及寻路校验仍由原流程负责。
func navigate_from_map(world_position: Vector2, point_id: StringName) -> void:
	if not point_id.is_empty():
		for point: MapNavigationPoint in active_world_controller.navigation_points():
			if point.id == point_id:
				move_to(point.destination, point.transition_id)
				return
		hud.show_status("目的地已不在当前地图，请重新选择")
		return
	if world_position.is_finite() and active_world_controller.definition != null \
			and Rect2(Vector2.ZERO, active_world_controller.map_size).has_point(world_position):
		move_to(world_position)
