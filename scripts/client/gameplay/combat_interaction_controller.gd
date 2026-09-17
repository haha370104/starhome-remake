class_name CombatInteractionController
extends Node

signal target_repair_requested(world_position: Vector2)

const CombatActions := preload("res://scripts/client/gameplay/client_combat_actions.gd")

var vehicle_destroyed := false
var application_exiting := false
var vehicle_destroyed_dialog: VehicleDestroyedDialog
var world_view: ClientWorldView
var local_player_controller: LocalPlayerController
var hud: HallHud
var map_travel: MapTravelController
var multiplayer_presenter: HallMultiplayerPresenter
var panel_session: PlayerPanelSession


## 绑定战斗表现和本地输入所需的显式依赖。
## [param view] 当前世界的玩家、怪物、掉落与特效视图。
## [param movement] 管理移动与动作恢复的本地控制器。
## [param display] 语义状态提示和动作选择接口。
## [param travel] 切图输入冻结与停步协调器。
func configure(
	view: ClientWorldView,
	movement: LocalPlayerController,
	display: HallHud,
	travel: MapTravelController,
) -> void:
	world_view = view
	local_player_controller = movement
	hud = display
	map_travel = travel


## 在会话启动前提供命令通道与共享玩家投影。
## [param presenter] 发送意图和接收权威结果的会话表现器。
## [param panels] 与所有窗口共享的玩家状态。
func bind_session(
	presenter: HallMultiplayerPresenter,
	panels: PlayerPanelSession,
) -> void:
	multiplayer_presenter = presenter
	panel_session = panels


## 点击矿物前检查当前玩家聚合中的实际主装置，避免把背包内采掘臂当成已装备。
## [param source_position] 所点击矿源的世界坐标。
## 设计：客户端只做即时拒绝提示；许可、产出和经验仍由服务器再次校验。
func request_mining(source_position: Vector2) -> void:
	var current_player: Player = panel_session.current_player if panel_session != null else null
	if current_player == null or current_player.vehicle == null:
		hud.show_system_message("角色装备数据尚未就绪，请稍后再试")
		return
	var allowed := current_player.vehicle.loadout.validate_mining(current_player.skills.base_level("mining"))
	if not allowed.is_ok:
		var notice := PlayerErrorMessages.describe(allowed.error_code, allowed.error_message)
		hud.show_status(notice)
		hud.show_system_message(notice)
		return
	# 本地传输可能同步收到拒绝或开始事件，不能在返回后用“正在准备”覆盖其结果。
	hud.show_status("正在请求采矿")
	if multiplayer_presenter.request_use_ability("mining.collect", source_position).is_empty():
		hud.show_status("采矿请求发送失败")


## 优先拾取掉落，再按选中槽位及实际主装置分发采矿、维修或武器意图。
## [param world_position] 鼠标命中的地图世界坐标。
## 设计：点击只提交开火意图；弹体、能耗和命中均由服务端接受事件驱动。
func handle_world_combat_left_click(world_position: Vector2) -> void:
	if world_view.ground_loot_world_controller != null:
		var loot_id := world_view.ground_loot_world_controller.loot_at(world_position)
		if not loot_id.is_empty():
			request_ground_loot_pickup(loot_id)
			return
	request_weapon_attack(world_position)


## 按当前装置发起意图，供手动点击与智脑共用；智脑先排除工程臂，手动点击保留工程臂分发。
## [param world_position] 已选中的目标世界坐标。
func request_weapon_attack(world_position: Vector2) -> void:
	var selected_mode := String(hud.selected_action())
	if selected_mode == "energy_cannon" and _handle_primary_device_click(world_position):
		return
	var mode: Dictionary = CombatActions.WEAPON_MODES.get(selected_mode, {})
	var attack_controller: Node = world_view.combat_attack_controllers.get(selected_mode)
	if mode.is_empty() or attack_controller == null:
		hud.show_status("武器表现尚未初始化")
		return
	var target_entity_id := world_view.monster_world_controller.nearest_target(world_position)
	if selected_mode == "missile" and target_entity_id.is_empty():
		hud.show_status("导弹需要锁定一个怪物")
		return
	var authoritative_target := world_position
	if not target_entity_id.is_empty():
		authoritative_target = world_view.monster_world_controller.target_position(target_entity_id)
	if not authoritative_target.is_finite():
		hud.show_status("目标已离开当前地图")
		return
	var tracking_resolver := Callable()
	if selected_mode == "missile":
		tracking_resolver = _combat_target_position.bind(target_entity_id)
	var result: Dictionary = attack_controller.request_fire(
		world_view.player.position, authoritative_target, tracking_resolver, true
	)
	if not bool(result.get("ok", false)):
		var code := StringName(result.get("code", &""))
		if code == &"cooldown":
			hud.show_status("%s冷却中" % String(mode["display_name"]))
		elif code == &"target_too_close":
			hud.show_status("射击目标距离过近")
		else:
			hud.show_status("当前无法开火")
		return
	var resolved_target: Vector2 = result["resolved_target"]
	hud.show_status("正在请求开火")
	var ability_payload: Dictionary = multiplayer_presenter.request_use_ability(
		String(mode["ability_id"]), resolved_target
	)
	var trace_fields := {
		"visual_shot_id": String(result.get("visual_shot_id", "")),
		"input_sequence": int(ability_payload.get("input_sequence", -1)),
		"ability_id": String(mode["ability_id"]),
		"weapon_mode": selected_mode,
		"map_instance_id": map_travel.multiplayer_map_instance_id,
		"actor_view_position": world_view.player.position,
		"clicked_world_position": world_position,
		"submitted_aim_position": resolved_target,
		"client_selected_target_entity_id": target_entity_id,
		"client_selected_target_position": authoritative_target,
		"moving_during_fire": local_player_controller.has_active_route(),
	}
	if ability_payload.is_empty():
		CombatTraceLogger.record(&"client", &"ability_intent_not_submitted", trace_fields)
		return
	CombatTraceLogger.record(&"client", &"ability_intent_submitted", trace_fields)


## 播放本玩家已经被服务器接受的攻击，拒绝开火时不会产生炮弹或炮口动画。
## [param event] 权威发射事件；其他玩家或非发射事件直接忽略。
func _present_confirmed_attack(event: Dictionary) -> void:
	var mode_id := String(event.get("skill_id", ""))
	if String(event.get("event_type", "")) != mode_id + "_projectile_spawned":
		return
	var local_id := String(multiplayer_presenter.session.local_entity_id) if multiplayer_presenter != null and multiplayer_presenter.session != null else ""
	if local_id.is_empty() or String(event.get("attacker_id", "")) != local_id:
		return
	var controller: WeaponAttackVisualController = world_view.combat_attack_controllers.get(mode_id)
	if controller == null:
		return
	var resolver := _combat_target_position.bind(String(event.get("target_entity_id", ""))) if mode_id == "missile" else Callable()
	if not controller.present_confirmed_shot(event, resolver, world_view.player.position):
		return
	# 副武器只有弹体表现；不能替换主装置或改变其动作和朝向。
	if mode_id != "energy_cannon":
		return
	var direction: Array = event.get("direction", [1, 0])
	var layer_id := &"primary_weapon"
	world_view.player.set_combat_layer_pose(layer_id, &"attack", LocalPlayerController.direction_index(Vector2(direction[0], direction[1])))
	_restore_locomotion_after_attack(local_player_controller.has_active_route(), layer_id)



## 根据实际主装置消费工程臂点击，能量炮继续进入既有开火流程。
## [param world_position] 用户点击的世界坐标。
## 返回是否已消费点击；主装置缺失时阻止按旧炮槽标识误开火。
func _handle_primary_device_click(world_position: Vector2) -> bool:
	var current: Player = panel_session.current_player if panel_session != null else null
	if current == null or current.vehicle == null:
		hud.show_status("角色装备数据尚未就绪，请稍后再试")
		return true
	var device: VehicleEquipment = current.vehicle.loadout.at(1)
	var kind := device.primary_device_kind() if device != null else ""
	match kind:
		"energy_cannon":
			return false
		"mining_arm":
			var minerals := world_view.mineral_world_controller
			var source_id := minerals.source_at(world_position) if minerals != null else ""
			if not source_id.is_empty():
				request_mining(minerals.source_position(source_id))
		"repair_arm":
			target_repair_requested.emit(world_position)
			hud.show_status("已选择维修目标，维修臂的目标维修功能尚未开放")
		_:
			hud.show_status("未安装可用主装置")
	return true


## 查询战斗目标在当前客户端快照中的世界坐标。
## [param target_entity_id] 需要跟踪的权威实体标识。
## 返回目标坐标；目标不可见时返回无穷坐标。
func _combat_target_position(target_entity_id: String) -> Vector2:
	return world_view.monster_world_controller.target_position(target_entity_id) \
		if world_view.monster_world_controller != null else Vector2.INF


## 向当前权威边界提交一次地面掉落拾取意图。
## [param loot_id] 鼠标命中的掉落实例标识。
## 设计：客户端只选择目标；距离、背包容量、入账和地面实体删除均由权威规则决定。
func request_ground_loot_pickup(loot_id: String) -> void:
	if multiplayer_presenter.request_loot_pickup(loot_id).is_empty():
		hud.show_status("拾取请求发送失败")


## 通过离线或正式网络权威边界请求开始战车自维修。
## 设计：键盘与顶部按钮复用此入口；生命、能量和技能许可仍由服务器决定。
func request_self_repair() -> void:
	if is_input_locked() or world_view.player == null or not world_view.player.is_combat_actor_active():
		hud.show_status("当前地图不能使用自维修")
		return
	var submitted: bool = not multiplayer_presenter.request_use_ability(
		CombatActions.SELF_REPAIR_ABILITY_ID, world_view.player.position
	).is_empty()
	if submitted:
		hud.show_status("已开始自维修：每3秒恢复一次生命")


## 在短促炮口动作结束后恢复开火前的移动状态。
## [param was_moving] 开火前是否正在沿路径移动。
## [param layer_id] 本次开火临时切换动作的武器图层标识。
## 设计：等待期间若路线自然结束则恢复站立；仍在移动时从当前路径段重算朝向。
func _restore_locomotion_after_attack(was_moving: bool, layer_id: StringName) -> void:
	await get_tree().create_timer(0.16).timeout
	if world_view.player == null or not world_view.player.is_combat_actor_active():
		return
	world_view.player.clear_combat_layer_action(layer_id)
	if was_moving and local_player_controller.has_active_route():
		local_player_controller.refresh_route_direction()
	else:
		local_player_controller.set_character_action(&"stand")


## 把权威战斗快照分发给实体视图、HUD 和战车击毁状态。
## [param snapshot] 会话已接收的战斗实体和本地战车快照。
func on_combat_snapshot_received(snapshot: Dictionary) -> void:
	world_view.mining_visual_controller.apply_snapshot(snapshot)
	for event: Dictionary in snapshot.get("recent_events", []):
		_present_confirmed_attack(event)
	for mode_id: String in world_view.combat_attack_controllers:
		var mode: Dictionary = CombatActions.WEAPON_MODES[mode_id]
		world_view.combat_attack_controllers[mode_id].apply_authoritative_snapshot(snapshot, String(mode["ability_id"]))
	hud.set_weapon_ammunition(snapshot.get("local_weapon_flight", {}))
	world_view.monster_world_controller.apply_snapshot(snapshot)
	if world_view.ground_loot_world_controller != null:
		world_view.ground_loot_world_controller.apply_snapshot(snapshot)
	if world_view.mineral_world_controller != null:
		world_view.mineral_world_controller.apply_snapshot(snapshot)
	var vehicle: Variant = snapshot.get("local_vehicle", {})
	if vehicle is Dictionary:
		world_view.player.set_combat_status(vehicle)
		hud.set_vehicle_combat_state(vehicle)
		# 非战斗地图仍同步战车资源供 HUD/面板消费，但人物移动不受停放战车生命值影响。
		var combat_vehicle_active := bool(
			snapshot.get("vehicle_combat_active", world_view.player.is_combat_actor_active())
		)
		var destroyed := combat_vehicle_active and int(vehicle.get("health", 0)) <= 0
		world_view.player.set_vehicle_destroyed(destroyed)
		if destroyed and not vehicle_destroyed:
			vehicle_destroyed = true
			map_travel.stop_moving("战车已被击毁")
			vehicle_destroyed_dialog.show_destroyed()
		elif not destroyed and vehicle_destroyed:
			vehicle_destroyed = false
			vehicle_destroyed_dialog.hide_dialog()
		if world_view.self_repair_visual_controller != null:
			world_view.self_repair_visual_controller.apply_snapshot(vehicle)


## 提交主动回城或击毁后的回基地选择；目的地图、三秒等待和回血规则均由服务器决定。
func request_vehicle_recovery() -> void:
	if application_exiting or map_travel.is_locked() or multiplayer_presenter == null:
		return
	map_travel.stop_moving("正在请求返回基地")
	if multiplayer_presenter.request_vehicle_recovery().is_empty():
		hud.show_system_message("返回基地请求发送失败")


## 显示服务器确认的基地救援等待时间。
## [param delay_seconds] 服务器安排的救援等待秒数。
func on_vehicle_recovery_scheduled(delay_seconds: float) -> void:
	if vehicle_destroyed:
		vehicle_destroyed_dialog.show_recovery_scheduled(delay_seconds)
	else:
		hud.show_system_message("将在 %.0f 秒后返回基地" % delay_seconds)


## 恢复被服务器拒绝的死亡窗选择。
## [param _code] 权威边界返回的稳定错误码。
## [param _message] 权威拒绝说明，界面通过错误映射呈现。
func on_vehicle_recovery_failed(_code: StringName, _message: String) -> void:
	if vehicle_destroyed:
		vehicle_destroyed_dialog.show_recovery_failed("基地救援请求被拒绝，请重试")
	else:
		hud.show_system_message(PlayerErrorMessages.describe(_code, _message))


## 原地等待只关闭选择窗，不解除击毁状态或恢复输入。
func on_destroyed_wait_selected() -> void:
	hud.show_status("正在原地等待其他玩家营救")


## 将已确认的战斗、维修、拾取和采矿事件转换为本地提示。
## [param event] 会话下发的已确认业务事件。
func on_combat_event_received(event: Dictionary) -> void:
	_present_confirmed_attack(event)
	var event_type := StringName(event.get("event_type", ""))
	if event_type == &"loot_picked_up":
		if world_view.ground_loot_world_controller != null:
			world_view.ground_loot_world_controller.remove_loot(String(event.get("loot_id", "")))
		hud.show_status("拾取了 %d 个物品" % int(event.get("quantity", 1)))
	elif event_type == &"mining_started":
		hud.show_status("开始采矿，每3秒采集一次")
	elif event_type == &"mining_collected":
		hud.show_status("采集到%s × %d（矿点剩余%d）" % [
			String(event.get("display_name", "矿物")),
			int(event.get("quantity", 1)),
			int(event.get("remaining", 0)),
		])
	elif event_type in [&"energy_cannon_hit", &"rocket_launcher_hit", &"missile_hit"]:
		hud.show_status("命中目标，造成%d点伤害（剩余%d）" % [
			int(event.get("damage", 0)),
			int(event.get("target_health", 0)),
		])
	elif event_type == &"self_repair_resolved":
		hud.show_status("自维修恢复%d点生命（当前%d）" % [
			int(event.get("healed", 0)),
			int(event.get("target_health", 0)),
		])
	elif event_type == &"self_repair_stopped":
		var reason := StringName(event.get("reason", &""))
		hud.show_status("战车已修复完成" if reason == &"full_health" else "自维修已停止")


## 合并切图、基地救援等待和战车击毁状态，供输入协调器使用。
## 返回世界操作是否必须暂停。
func is_input_locked() -> bool:
	return application_exiting or map_travel.is_locked() or vehicle_destroyed or (multiplayer_presenter != null \
		and multiplayer_presenter.session != null and multiplayer_presenter.session.is_vehicle_recovery_pending())

