class_name CombatInteractionController
extends Node

const CombatActions := preload("res://scripts/client/gameplay/client_combat_actions.gd")

var vehicle_destroyed := false
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
func configure(view: ClientWorldView, movement: LocalPlayerController, display: HallHud, travel: MapTravelController) -> void:
	world_view = view
	local_player_controller = movement
	hud = display
	map_travel = travel


## 在会话启动前提供命令通道与共享玩家投影。
## [param presenter] 发送意图和接收权威结果的会话表现器。
## [param panels] 与所有窗口共享的玩家状态。
func bind_session(presenter: HallMultiplayerPresenter, panels: PlayerPanelSession) -> void:
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


## 执行 `handle_world_combat_left_click` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：当前切片立即反馈弹体与命中特效；伤害、能耗和真实命中仍只接受服务端事件。
func handle_world_combat_left_click(world_position: Vector2) -> void:
	if world_view.ground_loot_world_controller != null:
		var loot_id := world_view.ground_loot_world_controller.loot_at(world_position)
		if not loot_id.is_empty():
			request_ground_loot_pickup(loot_id)
			return
	if world_view.mineral_world_controller != null:
		var source_id := world_view.mineral_world_controller.source_at(world_position)
		if not source_id.is_empty():
			var source_position := world_view.mineral_world_controller.source_position(source_id)
			request_mining(source_position)
			return
	var selected_mode := String(hud.selected_action())
	if selected_mode == "energy_cannon" and panel_session != null \
			and panel_session.current_player != null \
			and panel_session.current_player.vehicle != null:
		var primary_device: VehicleEquipment = panel_session.current_player.vehicle.loadout.at(1)
		if primary_device != null and primary_device.primary_device_kind() in ["mining_arm", "repair_arm"]:
			# 工程臂点击空地不提交开炮意图；上面的拾取和矿物选择仍保留各自的交互。
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
		world_view.player.position, authoritative_target, tracking_resolver
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
	attack_controller.bind_input_sequence(
		String(result["visual_shot_id"]), int(ability_payload["input_sequence"])
	)
	var was_moving: bool = local_player_controller.has_active_route()
	var direction: Vector2 = result["direction"]
	var weapon_direction := LocalPlayerController.direction_index(direction)
	var layer_id := StringName(mode["layer_id"])
	world_view.player.set_combat_weapon_layer(layer_id)
	world_view.player.set_combat_layer_pose(layer_id, &"attack", weapon_direction)
	if bool(result.get("range_clamped", false)):
		hud.show_status("目标超出射程，向极限点 %d, %d 开火" % [
			roundi(resolved_target.x),
			roundi(resolved_target.y),
		])
	else:
		hud.show_status("向 %d, %d 开火" % [
			roundi(resolved_target.x),
			roundi(resolved_target.y),
		])
	_restore_locomotion_after_attack(was_moving, layer_id)


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
## 设计：`Z` 与顶部按钮复用此入口；客户端只读取离线调试等级，不自行修改生命或能量。
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
## [param was_moving] 调用方传入的参数；具体约束由函数签名和所在模块定义。
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


## 处理 `on_combat_snapshot_received` 对应的信号回调。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func on_combat_snapshot_received(snapshot: Dictionary) -> void:
	world_view.mining_visual_controller.apply_snapshot(snapshot)
	for mode_id: String in world_view.combat_attack_controllers:
		var mode: Dictionary = CombatActions.WEAPON_MODES[mode_id]
		world_view.combat_attack_controllers[mode_id].apply_authoritative_snapshot(snapshot, String(mode["ability_id"]))
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


## 提交击毁后的回基地选择；目的地图、三秒等待和回血比例均由服务器决定。
func request_vehicle_recovery() -> void:
	if not vehicle_destroyed or multiplayer_presenter == null:
		return
	if multiplayer_presenter.request_vehicle_recovery().is_empty():
		vehicle_destroyed_dialog.show_recovery_failed("基地救援请求发送失败")


## 显示服务器确认的基地救援等待时间。
## [param delay_seconds] 调用方传入的 `delay_seconds` 参数。
func on_vehicle_recovery_scheduled(delay_seconds: float) -> void:
	vehicle_destroyed_dialog.show_recovery_scheduled(delay_seconds)


## 恢复被服务器拒绝的死亡窗选择。
## [param _code] 调用方传入的 `_code` 参数。
## [param _message] 调用方传入的 `_message` 参数。
func on_vehicle_recovery_failed(_code: StringName, _message: String) -> void:
	vehicle_destroyed_dialog.show_recovery_failed("基地救援请求被拒绝，请重试")


## 原地等待只关闭选择窗，不解除击毁状态或恢复输入。
func on_destroyed_wait_selected() -> void:
	hud.show_status("正在原地等待其他玩家营救")


## 处理 `on_combat_event_received` 对应的信号回调。
## [param event] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func on_combat_event_received(event: Dictionary) -> void:
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


## 响应底栏武器槽选择并切换玩家战车的可见武器图层。
## [param slot_id] 被选中的底栏武器槽标识。
func on_weapon_slot_selected(slot_id: String) -> void:
	var mode: Dictionary = CombatActions.WEAPON_MODES.get(slot_id, {})
	if world_view.player != null and not mode.is_empty():
		world_view.player.set_combat_weapon_layer(StringName(mode["layer_id"]))


## 合并切图冻结和战车击毁状态，供输入协调器使用。
## 返回世界操作是否必须暂停。
func is_input_locked() -> bool:
	return map_travel.is_locked() or vehicle_destroyed

