class_name PlayerPresentationBinding
extends RefCounted

var world_view: ClientWorldView
var local_player_controller: LocalPlayerController
var active_world_controller: ActiveWorldController
var hud: HallHud
var panel_session: PlayerPanelSession
var character_catalog: Dictionary


## 连接世界头像、相机、HUD 与移动许可的展示依赖。
## [param view] 同时支持人物与战车的世界视图。
## [param movement] 唯一移动状态所有者。
## [param world] 提供当前地图类别的世界所有者。
## [param display] HUD 语义接口。
## [param catalog] 已加载的人物服装表现目录。
func configure(
	view: ClientWorldView,
	movement: LocalPlayerController,
	world: ActiveWorldController,
	display: HallHud,
	catalog: Dictionary,
) -> void:
	world_view = view
	local_player_controller = movement
	active_world_controller = world
	hud = display
	character_catalog = catalog


## 将本地控制器发出的最终坐标同步到相机和小地图，不写回玩家位置。
## [param position] 已应用预测或权威校正的世界坐标。
func sync_position(position: Vector2) -> void:
	world_view.camera.position = position
	hud.update_player_dot(position)


## 将线上或离线权威升级事件格式化为荣耀版原句式并交给 HUD 排队。
## [param event] 含 skill_id 与 new_level 的权威升级事件。
func on_skill_level_up(event: Dictionary) -> void:
	if hud == null:
		return
	hud.show_system_message(SkillLevelMessageFormatter.format(
		String(event.get("skill_id", "")), int(event.get("new_level", 0))
	))


## 将客户端唯一 CurrentPlayer 的服装对象同步到世界人物表现。
## [param current_player] 刚应用同事务权威快照的当前玩家聚合。
func on_current_player_changed(current_player: Player) -> void:
	if world_view.player != null:
		world_view.player.apply_character_equipment(
			current_player.character_equipment,
			character_catalog,
		)
		world_view.player.apply_vehicle_equipment(current_player.vehicle)
	if hud != null:
		var primary_device: VehicleEquipment = current_player.vehicle.loadout.at(1)
		hud.set_primary_device("" if primary_device == null else primary_device.primary_device_kind())
		var tactical_equipment := current_player.vehicle.loadout.at(13) as VehicleWeapon
		var action_id := "" if tactical_equipment == null else tactical_equipment.combat_mode()
		hud.set_tactical_action(action_id)
	refresh_local_movement_availability(current_player)


## 根据活动地图与权威玩家装配刷新本地预测移动许可。
## 室内始终按人物移动；野外必须存在提供正推进力的引擎。
## [param current_player] 最新玩家聚合；为空时从当前面板投影读取。
func refresh_local_movement_availability(current_player: Player = null) -> void:
	if local_player_controller == null or active_world_controller.definition == null:
		return
	var player_state := current_player
	if player_state == null and panel_session != null:
		player_state = panel_session.current_player
	var movement_enabled := true
	if active_world_controller.definition.category == "field":
		movement_enabled = player_state != null \
			and int(player_state.calculate_vehicle_stats().get("propulsion", 0)) > 0
	local_player_controller.set_movement_enabled(movement_enabled)
