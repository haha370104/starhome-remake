class_name MapTravelController
extends Node

signal map_committed

var active_world_controller: ActiveWorldController
var local_player_controller: LocalPlayerController
var player: PlayerWorldAvatar
var hud: HallHud
var multiplayer_presenter: HallMultiplayerPresenter
var map_preloader: ClientMapPreloader
var map_route_resolver: RuntimeMapRouteResolver
var initial_loading_screen: CanvasLayer
var multiplayer_map_instance_id := ""
var map_transition_trigger_radius := 64.0
var pending_map_transition: Dictionary = {}
var pending_map_bundle: Dictionary = {}
var pending_authoritative_join: Dictionary = {}
var map_commit_failure_locked := false
var selected_transition_id: StringName = &""
var _initial_authoritative_world_ready := false


## 注入切图所需的场景提交、移动与提示端口。
## [param world] 唯一活动地图所有者。
## [param movement] 唯一本地位置与路径所有者。
## [param avatar] 提供出口距离计算的玩家视图。
## [param display] 语义 HUD 接口。
func configure(
	world: ActiveWorldController,
	movement: LocalPlayerController,
	avatar: PlayerWorldAvatar,
	display: HallHud,
) -> void:
	active_world_controller = world
	local_player_controller = movement
	player = avatar
	hud = display


## 绑定已构造的会话与地图预载器，必须在启动会话前完成。
## [param presenter] 发送切图意图并提供会话状态的表现器。
## [param preloader] 仅加载受控目录的地图资源。
## [param resolver] 将旧地图代码解析为受控业务 ID。
## [param loading] 首次权威世界就绪前的启动遮罩。
func bind_session(
	presenter: HallMultiplayerPresenter,
	preloader: ClientMapPreloader,
	resolver: RuntimeMapRouteResolver,
	loading: CanvasLayer,
) -> void:
	multiplayer_presenter = presenter
	map_preloader = preloader
	map_route_resolver = resolver
	initial_loading_screen = loading


## 在首份权威地图完成原子提交后移除启动遮罩；重复调用不会影响后续地图切换。
func finish_initial_loading() -> void:
	if _initial_authoritative_world_ready:
		return
	_initial_authoritative_world_ready = true
	if initial_loading_screen != null:
		initial_loading_screen.finish_loading()


## 在初始权威会话失败时保留遮罩并展示可读错误，避免回退到并非玩家存档位置的大厅。
## [param message] 传输层或权威握手返回的失败原因。
func on_initial_connection_failed(message: String) -> void:
	if _initial_authoritative_world_ready or initial_loading_screen == null:
		return
	push_warning("Initial connection failed: %s" % message)
	initial_loading_screen.set_status(PlayerErrorMessages.describe(&"connection.failed", message))


## 在玩家停步后查找触发半径内最近的内部出口，并先预载其目标地图。
## 设计：客户端只从受控本地定义取得目标内容；真正的地图和落点仍由服务端裁决。
func try_begin_nearby_map_transition() -> void:
	if not pending_map_transition.is_empty() or map_preloader == null:
		return
	var selected_transition: MapTransition
	var selected_destination_map_id: StringName = &""
	var selected_distance := map_transition_trigger_radius
	if not selected_transition_id.is_empty():
		var requested_transition: MapTransition = active_world_controller.definition.transition_by_id(selected_transition_id)
		if requested_transition != null:
			var requested_destination_map_id := resolve_transition_destination_id(
				requested_transition
			)
			if requested_destination_map_id.is_empty():
				selected_transition_id = &""
				hud.show_status("地图%s已识别，但运行资源尚未导入" % [
					requested_transition.destination_key().to_upper(),
				])
				return
			var requested_distance := player.position.distance_to(requested_transition.approach_point)
			if requested_distance <= selected_distance:
				selected_transition = requested_transition
				selected_destination_map_id = requested_destination_map_id
				selected_distance = requested_distance
	else:
		for transition: MapTransition in active_world_controller.definition.enabled_transitions():
			var destination_map_id := resolve_transition_destination_id(transition)
			if destination_map_id.is_empty():
				continue
			var distance := player.position.distance_to(transition.approach_point)
			if distance <= selected_distance:
				selected_transition = transition
				selected_destination_map_id = destination_map_id
				selected_distance = distance
	selected_transition_id = &""
	if selected_transition == null:
		return
	pending_map_transition = {
		"transition_id": selected_transition.transition_id,
		"destination_map_id": selected_destination_map_id,
		"destination_entry_number": selected_transition.destination_entry_number,
	}
	hud.show_status("正在准备前往%s…" % selected_transition.label)
	var preload_error: Error = map_preloader.preload_map(
		selected_destination_map_id
	)
	if preload_error != OK and not pending_map_transition.is_empty():
		pending_map_transition.clear()


## 使用与权威服务器相同的世界内旧代码规则解析预载目标，但仅返回受控内容目录中的地图。
## [param transition] 当前活动地图内待解析的出口。
## 返回允许客户端预载的运行时地图 ID；未导入目标返回空值。
func resolve_transition_destination_id(transition: MapTransition) -> StringName:
	if map_route_resolver != null:
		return map_route_resolver.resolve_target_id(transition, active_world_controller.definition.world_id)
	return transition.destination_map_id


## 在资源就绪后提交切图意图，或完成已经确认的权威地图提交。
## [param map_id] 受控目录中的业务地图标识。
## [param bundle] 地图预载器返回的已准备资源包。
func on_map_preload_ready(map_id: StringName, bundle: Dictionary) -> void:
	if (
		not pending_authoritative_join.is_empty()
		and StringName(pending_authoritative_join.get("map_id", &"")) == map_id
	):
		var join := pending_authoritative_join.duplicate(true)
		pending_authoritative_join.clear()
		var joined_spawn_position: Vector2 = join["spawn_position"]
		if not commit_map_bundle(bundle, joined_spawn_position, String(join["map_instance_id"])):
			handle_map_commit_failure("权威地图资源提交失败")
		return
	if (
		pending_map_transition.is_empty()
		or StringName(pending_map_transition.get("destination_map_id", &"")) != map_id
	):
		return
	pending_map_bundle = bundle
	var request: Dictionary = multiplayer_presenter.request_map_change(
		StringName(pending_map_transition["transition_id"]),
		int(pending_map_transition["destination_entry_number"]),
	)
	if request.is_empty():
		hud.show_status("当前无法提交地图切换请求")
		pending_map_transition.clear()
		pending_map_bundle.clear()


## 区分权威确认前后的加载失败，分别回滚请求或冻结旧场景。
## [param map_id] 受控目录中的业务地图标识。
## [param message] 当前流程产生的失败或状态说明。
func on_map_preload_failed(map_id: StringName, message: String) -> void:
	push_warning("Map preload failed [%s]: %s" % [map_id, message])
	var notice := PlayerErrorMessages.describe(&"map.load_failed")
	if not pending_authoritative_join.is_empty():
		pending_authoritative_join.clear()
		handle_map_commit_failure(notice)
		return
	hud.show_status(notice)
	pending_map_transition.clear()
	pending_map_bundle.clear()


## 接受权威地图与落点；资源未就绪时保持旧画面直到预载完成。
## [param map_id] 受控目录中的业务地图标识。
## [param map_instance_id] 服务器确认的目标地图实例标识。
## [param spawn_position] 服务器决定的目标世界坐标。
## [param _definition_version] 权威地图定义版本，版本校验由会话层负责。
func on_authoritative_map_joined(
	map_id: StringName,
	map_instance_id: String,
	spawn_position: Vector2,
	_definition_version: int,
) -> void:
	if active_world_controller.definition.map_id == map_id:
		stop_moving("正在载入权威地图…")
		map_commit_failure_locked = false
		multiplayer_map_instance_id = map_instance_id
		local_player_controller.set_position(spawn_position)
		stop_moving("已进入%s" % active_world_controller.definition.display_name)
		pending_map_transition.clear()
		pending_map_bundle.clear()
		finish_initial_loading()
		return
	if (
		not pending_map_bundle.is_empty()
		and pending_map_bundle["definition"].map_id == map_id
	):
		if not commit_map_bundle(pending_map_bundle, spawn_position, map_instance_id):
			handle_map_commit_failure("权威地图资源提交失败")
		return
	hold_old_map_for_authoritative_join(map_id, map_instance_id, spawn_position)
	var preload_error: Error = map_preloader.preload_map(map_id)
	if preload_error != OK and not pending_authoritative_join.is_empty():
		handle_map_commit_failure("客户端缺少权威地图资源")


## 记录待提交的权威落点并暂停旧地图的路径与预测。
## [param map_id] 受控目录中的业务地图标识。
## [param map_instance_id] 服务器确认的目标地图实例标识。
## [param spawn_position] 服务器决定的目标世界坐标。
## 设计：立即终止旧路径；新出生点由 session 持有，但旧场景直到 bundle 提交前不呈现它。
func hold_old_map_for_authoritative_join(
	map_id: StringName,
	map_instance_id: String,
	spawn_position: Vector2,
) -> void:
	var held_player_position: Vector2 = local_player_controller.position()
	local_player_controller.hold_position_for_map_commit()
	hud.show_status("正在载入权威地图…")
	pending_authoritative_join = {
		"map_id": map_id,
		"map_instance_id": map_instance_id,
		"spawn_position": spawn_position,
		"held_player_position": held_player_position,
	}


## 在权威切图拒绝时清空对应预载包；旧地图画面和导航保持不变。
## [param _transition_id] 被拒绝请求的出口标识。
## [param _code] 权威边界返回的稳定错误码。
## [param _message] 权威拒绝说明，界面通过错误映射呈现。
func on_authoritative_map_change_failed(
	_transition_id: StringName,
	_code: StringName,
	_message: String,
) -> void:
	pending_map_transition.clear()
	pending_map_bundle.clear()
	pending_authoritative_join.clear()


## 通过活动世界执行原子替换，再更新会话标识、输入闸门与加载遮罩。
## [param bundle] 地图预载器返回的已准备资源包。
## [param spawn_position] 服务器决定的目标世界坐标。
## [param map_instance_id] 服务器确认的目标地图实例标识。
## 返回资源是否成功提交；失败时旧地图保持不变。
## 设计：所有可失败加载均先暂存，当前场景直到验证完成才被清理。
func commit_map_bundle(
	bundle: Dictionary,
	spawn_position: Vector2,
	map_instance_id: String,
) -> bool:
	if not active_world_controller.commit_bundle(bundle, spawn_position):
		return false
	map_committed.emit()
	multiplayer_map_instance_id = map_instance_id
	local_player_controller.set_character_action(&"stand")
	hud.show_status("已进入%s" % active_world_controller.definition.display_name)
	map_commit_failure_locked = false
	pending_map_transition.clear()
	pending_map_bundle.clear()
	finish_initial_loading()
	return true


## 终止无法呈现权威地图的会话，保留错误提示并锁住旧世界输入。
## [param message] 当前流程产生的失败或状态说明。
func handle_map_commit_failure(message: String) -> void:
	push_warning("Map commit failed: %s" % message)
	var notice := PlayerErrorMessages.describe(&"map.load_failed", message)
	map_commit_failure_locked = true
	stop_moving(notice)
	if not _initial_authoritative_world_ready and initial_loading_screen != null:
		initial_loading_screen.set_status(notice)
	pending_map_transition.clear()
	pending_map_bundle.clear()
	pending_authoritative_join.clear()
	if multiplayer_presenter:
		multiplayer_presenter.stop()


## 取消当前路线和出口选择，同时显示停步原因。
## [param message] 当前流程产生的失败或状态说明。
func stop_moving(message: String) -> void:
	if local_player_controller:
		local_player_controller.cancel_route()
	selected_transition_id = &""
	if hud:
		hud.show_status(message)


## 报告旧地图世界输入是否必须暂停，直到切图完成、失败回滚或会话被安全关闭。
## 返回切图事务是否禁止新的世界操作。
## 设计：闸门只冻结本地世界交互；服务端拒绝会清空 pending 并恢复旧地图输入。
func is_locked() -> bool:
	if map_commit_failure_locked:
		return true
	if (
		not pending_map_transition.is_empty()
		or not pending_authoritative_join.is_empty()
	):
		return true
	if multiplayer_presenter == null or multiplayer_presenter.session == null:
		return false
	return multiplayer_presenter.session.is_map_change_pending()
