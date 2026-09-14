extends Node2D

const CHARACTER_CATALOG_PATH := "res://assets/characters/character_atlases.json"
const COMBAT_VISUAL_MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"
const MINING_VISUAL_MANIFEST_PATH := "res://assets/minerals/mining_asset_manifest.json"
const NPC_CONFIG_PATH := "res://data/npcs/yian_harbor_hall_floor_1.json"
const MAP_DEFINITION_PATH := "res://data/maps/yian_harbor_hall_floor_1.json"
const MAP_DIRECTORY_PATH := "res://data/maps/glory_map_directory_v1.json"
const RuntimeContentBootstrapScript := preload(
	"res://scripts/content/runtime_content_bootstrap.gd"
)
const DiamondNavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")
const CharacterFactoryScript := preload("res://scripts/characters/character_factory.gd")
const PlayerWorldAvatarScript := preload("res://scripts/characters/player_world_avatar.gd")
const HallHudScript := preload("res://scripts/ui/hall_hud.gd")
const HallMultiplayerPresenterScript := preload(
	"res://scripts/client/presentation/hall_multiplayer_presenter.gd"
)
const ClientMapPreloaderScript := preload(
	"res://scripts/client/presentation/client_map_preloader.gd"
)
const RuntimeMapRouteResolverScript := preload(
	"res://scripts/maps/runtime_map_route_resolver.gd"
)
const LocalPlayerControllerScript := preload(
	"res://scripts/client/gameplay/local_player_controller.gd"
)
const MovementClickEffectPresenterScript := preload(
	"res://scripts/client/presentation/movement_click_effect_presenter.gd"
)
const ActiveWorldControllerScript := preload(
	"res://scripts/client/world/active_world_controller.gd"
)
const WeaponAttackVisualControllerScript := preload(
	"res://scripts/client/presentation/combat/weapon_attack_visual_controller.gd"
)
const MonsterWorldControllerScript := preload(
	"res://scripts/client/presentation/combat/monster_world_controller.gd"
)
const GroundLootWorldControllerScript := preload(
	"res://scripts/client/presentation/combat/ground_loot_world_controller.gd"
)
const MineralWorldControllerScript := preload(
	"res://scripts/client/presentation/mining/mineral_world_controller.gd"
)
const SelfRepairVisualControllerScript := preload(
	"res://scripts/client/presentation/combat/self_repair_visual_controller.gd"
)
const GameWindowManagerScript := preload(
	"res://scripts/client/ui/windows/game_window_manager.gd"
)
const InitialLoadingScreenScript := preload(
	"res://scripts/client/ui/initial_loading_screen.gd"
)
const VehicleDestroyedDialogScript := preload(
	"res://scripts/ui/vehicle_destroyed_dialog.gd"
)
const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const WEAPON_MODES := {
	"energy_cannon": {
		"weapon_id": &"recruit_energy_cannon",
		"ability_id": "energy_cannon.primary",
		"layer_id": &"primary_weapon",
		"display_name": "新兵能量炮",
	},
	"missile": {
		"weapon_id": &"starter_missile",
		"ability_id": "missile.primary",
		"layer_id": &"missile_weapon",
		"display_name": "初级导弹",
	},
	"rocket_launcher": {
		"weapon_id": &"starter_rocket_launcher",
		"ability_id": "rocket_launcher.primary",
		"layer_id": &"rocket_weapon",
		"display_name": "初级火箭",
	},
}
const TACTICAL_ACTION_BY_DEFINITION := {
	"starter_rocket_launcher": "rocket_launcher",
	"starter_missile": "missile",
}
const SELF_REPAIR_ABILITY_ID := "self_repair"

# Player tuning is intentionally local to the player. NPC patrol motion has its
# own configuration and must not inherit these values when player progression,
# equipment or accessibility settings change them later.
@export_range(1.0, 600.0, 1.0) var player_movement_speed := 203.0
@export_range(0.1, 4.0, 0.05) var player_animation_speed_scale := 1.0

@export_category("Multiplayer")
@export var multiplayer_offline_debug_enabled := true
@export var multiplayer_connect_automatically := true
@export var multiplayer_server_host := "127.0.0.1"
@export_range(1, 65535, 1) var multiplayer_server_port := ClientNetworkAdapter.DEFAULT_PORT
@export var multiplayer_local_entity_id: StringName = &"player.local"
@export var multiplayer_map_instance_id := "yian_harbor_hall_floor_1.instance.1"
@export_range(1.0, 200.0, 1.0) var map_transition_trigger_radius := 64.0

var character_catalog: Dictionary
var npc_catalog: Dictionary
var active_world_controller: Node

# Public aliases delegate to ActiveWorldController so map diagnostics keep a
# stable surface without creating a second owner for activity state.
var map_manifest: Dictionary:
	get:
		return active_world_controller.map_manifest if active_world_controller else {}
var map_definition: RefCounted:
	get:
		return active_world_controller.definition if active_world_controller else null
var map_size: Vector2:
	get:
		return active_world_controller.map_size if active_world_controller else Vector2.ZERO
var navigation: RefCounted:
	get:
		return active_world_controller.navigation if active_world_controller else null
var nav_data: PackedByteArray:
	get:
		return navigation.data if navigation else PackedByteArray()
var nav_grid: AStar2D:
	get:
		return navigation.graph if navigation else null
var local_player_controller: Node

# Diagnostic compatibility properties expose the controller's one true state
# to existing validation fixtures without retaining a second route model here.
var path_points: PackedVector2Array:
	get:
		return local_player_controller.path_points if local_player_controller else PackedVector2Array()
	set(value):
		if local_player_controller:
			local_player_controller.path_points = value
var path_index: int:
	get:
		return local_player_controller.path_index if local_player_controller else 0
	set(value):
		if local_player_controller:
			local_player_controller.path_index = value
var current_direction: int:
	get:
		return local_player_controller.current_direction if local_player_controller else 6
	set(value):
		if local_player_controller:
			local_player_controller.current_direction = value

var sortable_world: Node2D
var map_background: Sprite2D
var map_scene_nodes: Array[Node2D]:
	get:
		return active_world_controller.scene_nodes if active_world_controller else []
var player: Node2D
var npc_instances: Array[Node2D]:
	get:
		return active_world_controller.npc_instances if active_world_controller else []
var facility_instances: Array[Node2D]:
	get:
		return active_world_controller.facility_instances if active_world_controller else []
var active_npc: Node2D
var camera: Camera2D
var movement_click_effects: MovementClickEffectPresenter
var hud: CanvasLayer
var hint_label: Label
var popup: PanelContainer
var minimap_player_dot: ColorRect
var multiplayer_presenter: Node
var map_preloader: Node
var map_route_resolver: RefCounted
var active_movement_input_sequence: int:
	get:
		return local_player_controller.active_movement_input_sequence if local_player_controller else 0
	set(value):
		if local_player_controller:
			local_player_controller.active_movement_input_sequence = value
var pending_map_transition: Dictionary = {}
var pending_map_bundle: Dictionary = {}
var pending_authoritative_join: Dictionary = {}
var map_commit_failure_locked := false
var selected_transition_id: StringName = &""
var transition_choice_ids: Dictionary = {}
var combat_attack_controller: Node
var combat_attack_controllers: Dictionary = {}
var monster_world_controller: MonsterWorldController
var ground_loot_world_controller: GroundLootWorldController
var mineral_world_controller: MineralWorldController
var self_repair_visual_controller: SelfRepairVisualController
var mining_visual_controller = preload("res://scripts/client/presentation/mining/mining_visual_controller.gd").new()
var panel_session: PlayerPanelSession
var game_window_manager: GameWindowManager
var item_catalog: ItemCatalog
var initial_loading_screen: CanvasLayer
var vehicle_destroyed_dialog: VehicleDestroyedDialog
var _vehicle_destroyed := false
var _initial_authoritative_world_ready := false


## 节点进入场景树后初始化运行依赖。
func _ready() -> void:
	_apply_multiplayer_command_line(OS.get_cmdline_user_args())
	_build_initial_loading_screen()
	var content_result: Dictionary = RuntimeContentBootstrapScript.mount_default()
	if not bool(content_result.get("ok", false)):
		push_error("Unable to mount Glory runtime content: %s" % content_result.get("message", ""))
		return
	character_catalog = JSON.parse_string(FileAccess.get_file_as_string(CHARACTER_CATALOG_PATH))
	npc_catalog = JSON.parse_string(FileAccess.get_file_as_string(NPC_CONFIG_PATH))
	active_world_controller = ActiveWorldControllerScript.new()
	active_world_controller.name = "ActiveWorldController"
	active_world_controller.active_world_will_replace.connect(_on_active_world_will_replace)
	add_child(active_world_controller)
	var initial_bundle: Dictionary = active_world_controller.prepare_initial_bundle(MAP_DEFINITION_PATH)
	if initial_bundle.is_empty():
		push_error("Unable to prepare initial map bundle")
		return
	_build_world()
	_build_hud(initial_bundle)
	var configure_error: Error = active_world_controller.configure(
		self,
		sortable_world,
		map_background,
		player,
		local_player_controller,
		camera,
		hud,
		character_catalog,
		npc_catalog,
	)
	if configure_error != OK:
		push_error("Unable to configure active world: %s" % error_string(configure_error))
		return
	var initial_definition: MapDefinition = initial_bundle["definition"]
	var initial_spawn: MapSpawnPoint = initial_definition.spawn_by_id(initial_definition.default_spawn_id)
	if initial_spawn == null or not active_world_controller.commit_bundle(initial_bundle, initial_spawn.position):
		push_error("Unable to commit initial map bundle")
		return
	_build_multiplayer_presentation()
	_set_player_action("stand")
	_sync_player_nodes()
	if not multiplayer_connect_automatically:
		_finish_initial_loading()


## 创建启动遮罩，阻止默认大厅在持久化角色地图尚未恢复时提前露出。
func _build_initial_loading_screen() -> void:
	initial_loading_screen = InitialLoadingScreenScript.new()
	initial_loading_screen.name = "InitialLoadingScreen"
	add_child(initial_loading_screen)
	initial_loading_screen.show_loading("正在读取角色与地图数据")


## 在首份权威地图完成原子提交后移除启动遮罩；重复调用不会影响后续地图切换。
func _finish_initial_loading() -> void:
	if _initial_authoritative_world_ready:
		return
	_initial_authoritative_world_ready = true
	if initial_loading_screen != null:
		initial_loading_screen.finish_loading()


## 在初始权威会话失败时保留遮罩并展示可读错误，避免回退到并非玩家存档位置的大厅。
## [param message] 传输层或权威握手返回的失败原因。
func _on_initial_connection_failed(message: String) -> void:
	if _initial_authoritative_world_ready or initial_loading_screen == null:
		return
	push_warning("Initial connection failed: %s" % message)
	initial_loading_screen.set_status(PlayerErrorMessages.describe(&"connection.failed", message))


## 执行 `apply_multiplayer_command_line` 对应的模块操作。
## [param arguments] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：编辑器默认保持离线调试；正式联机必须显式传入 `--online`，避免无服务器时影响美术预览。
func _apply_multiplayer_command_line(arguments: PackedStringArray) -> void:
	for argument in arguments:
		if argument == "--online":
			multiplayer_offline_debug_enabled = false
		elif argument == "--offline-debug":
			multiplayer_offline_debug_enabled = true
		elif argument == "--no-auto-connect":
			multiplayer_connect_automatically = false
		elif argument.begins_with("--server-host="):
			multiplayer_server_host = argument.trim_prefix("--server-host=")
		elif argument.begins_with("--server-port="):
			var requested_port := int(argument.trim_prefix("--server-port="))
			if requested_port >= 1 and requested_port <= 65535:
				multiplayer_server_port = requested_port


## 按渲染帧推进当前节点的表现状态。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _process(delta: float) -> void:
	if local_player_controller:
		local_player_controller.advance(delta)


## 接收并分发当前节点负责的输入事件。
## [param event] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_Z:
			_request_self_repair()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if _world_input_locked():
		get_viewport().set_input_as_handled()
		return
	var mouse_event := event as InputEventMouseButton
	var world_position := get_global_mouse_position()
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_world_right_click(world_position)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		var npc := _nearest_npc(world_position, 55.0)
		if npc:
			_show_npc_popup(npc)
		elif player != null and player.is_combat_actor_active():
			_handle_world_combat_left_click(world_position)
		else:
			hud.hide_popup()
		get_viewport().set_input_as_handled()


## 点击矿物前检查当前玩家聚合中的实际主装置，避免把背包内采掘臂当成已装备。
## [param source_position] 所点击矿源的世界坐标。
## 设计：客户端只做即时拒绝提示；许可、产出和经验仍由服务器再次校验。
func _request_mining(source_position: Vector2) -> void:
	var current_player: Player = panel_session.current_player if game_window_manager != null else null
	if current_player == null or current_player.vehicle == null:
		hud.show_system_message("角色装备数据尚未就绪，请稍后再试")
		return
	var allowed := current_player.vehicle.loadout.validate_mining(current_player.skills.base_level("mining"))
	if not allowed.is_ok:
		var notice := PlayerErrorMessages.describe(allowed.error_code, allowed.error_message)
		hint_label.text = notice
		hud.show_system_message(notice)
		return
	# 本地传输可能同步收到拒绝或开始事件，不能在返回后用“正在准备”覆盖其结果。
	hint_label.text = "正在请求采矿"
	if multiplayer_presenter.request_use_ability("mining.collect", source_position).is_empty():
		hint_label.text = "采矿请求发送失败"


## 执行 `handle_world_combat_left_click` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：当前切片立即反馈弹体与命中特效；伤害、能耗和真实命中仍只接受服务端事件。
func _handle_world_combat_left_click(world_position: Vector2) -> void:
	if ground_loot_world_controller != null:
		var loot_id := ground_loot_world_controller.loot_at(world_position)
		if not loot_id.is_empty():
			_request_ground_loot_pickup(loot_id)
			return
	if mineral_world_controller != null:
		var source_id := mineral_world_controller.source_at(world_position)
		if not source_id.is_empty():
			var source_position := mineral_world_controller.source_position(source_id)
			_request_mining(source_position)
			return
	var selected_mode := String(hud.state.selected_action_slot)
	if selected_mode == "energy_cannon" and game_window_manager != null \
			and panel_session.current_player != null \
			and panel_session.current_player.vehicle != null:
		var primary_device: VehicleEquipment = panel_session.current_player.vehicle.loadout.at(1)
		if primary_device != null and primary_device.primary_device_kind() in ["mining_arm", "repair_arm"]:
			# 工程臂点击空地不提交开炮意图；上面的拾取和矿物选择仍保留各自的交互。
			return
	var mode: Dictionary = WEAPON_MODES.get(selected_mode, {})
	var attack_controller: Node = combat_attack_controllers.get(selected_mode)
	if mode.is_empty() or attack_controller == null:
		hint_label.text = "武器表现尚未初始化"
		return
	var target_entity_id := monster_world_controller.nearest_target(world_position)
	if selected_mode == "missile" and target_entity_id.is_empty():
		hint_label.text = "导弹需要锁定一个怪物"
		return
	var authoritative_target := world_position
	if not target_entity_id.is_empty():
		authoritative_target = monster_world_controller.target_position(target_entity_id)
	if not authoritative_target.is_finite():
		hint_label.text = "目标已离开当前地图"
		return
	var tracking_resolver := Callable()
	if selected_mode == "missile":
		tracking_resolver = _combat_target_position.bind(target_entity_id)
	var result: Dictionary = attack_controller.request_fire(
		player.position, authoritative_target, tracking_resolver
	)
	if not bool(result.get("ok", false)):
		var code := StringName(result.get("code", &""))
		if code == &"cooldown":
			hint_label.text = "%s冷却中" % String(mode["display_name"])
		elif code == &"target_too_close":
			hint_label.text = "射击目标距离过近"
		else:
			hint_label.text = "当前无法开火"
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
		"map_instance_id": multiplayer_map_instance_id,
		"actor_view_position": player.position,
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
	var weapon_direction := _direction_index(direction)
	var layer_id := StringName(mode["layer_id"])
	player.set_combat_weapon_layer(layer_id)
	player.set_combat_layer_pose(layer_id, &"attack", weapon_direction)
	if bool(result.get("range_clamped", false)):
		hint_label.text = "目标超出射程，向极限点 %d, %d 开火" % [
			roundi(resolved_target.x),
			roundi(resolved_target.y),
		]
	else:
		hint_label.text = "向 %d, %d 开火" % [
			roundi(resolved_target.x),
			roundi(resolved_target.y),
		]
	_restore_locomotion_after_attack(was_moving, layer_id)


## 查询战斗目标在当前客户端快照中的世界坐标。
## [param target_entity_id] 需要跟踪的权威实体标识。
## 返回目标坐标；目标不可见时返回无穷坐标。
func _combat_target_position(target_entity_id: String) -> Vector2:
	return monster_world_controller.target_position(target_entity_id) \
		if monster_world_controller != null else Vector2.INF


## 向当前权威边界提交一次地面掉落拾取意图。
## [param loot_id] 鼠标命中的掉落实例标识。
## 设计：客户端只选择目标；距离、背包容量、入账和地面实体删除均由权威规则决定。
func _request_ground_loot_pickup(loot_id: String) -> void:
	if multiplayer_presenter.request_loot_pickup(loot_id).is_empty():
		hint_label.text = "拾取请求发送失败"


## 将拾取领域错误转换为玩家可理解的状态文字。
## [param code] 服务端或离线权威返回的稳定错误码。
## 返回简短中文提示。
func _loot_rejection_text(code: StringName) -> String:
	match code:
		&"loot.out_of_range": return "距离物品太远，无法拾取"
		&"inventory.full", &"inventory.no_space": return "背包空间不足"
		&"loot.not_found": return "物品已被其他玩家拾取"
		_: return "当前无法拾取该物品"


## 执行 `combat_rejection_text` 对应的模块操作。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _combat_rejection_text(code: StringName) -> String:
	match code:
		&"combat.target_out_of_range":
			return "目标超出新兵能量炮射程"
		&"combat.weapon_cooldown":
			return "新兵能量炮冷却中"
		&"combat.insufficient_working_energy":
			return "当前能量不足"
		&"combat.target_already_dead":
			return "目标已经被击败"
		&"combat.self_repair_not_needed":
			return "战车生命已满，无需维修"
		&"combat.repair_skill_insufficient":
			return "维修技能等级不足，无法启动当前战车的自维修器"
		&"combat.self_repair_unavailable":
			return "当前战车没有可用的自维修器"
		&"combat.vehicle_destroyed":
			return "战车已损毁，无法自维修"
		&"combat.not_available":
			return "当前地图不能使用自维修"
		_:
			return "本次攻击未被权威战斗系统接受"


## 通过离线或正式网络权威边界请求开始战车自维修。
## 设计：`Z` 与顶部按钮复用此入口；客户端只读取离线调试等级，不自行修改生命或能量。
func _request_self_repair() -> void:
	if _world_input_locked() or player == null or not player.is_combat_actor_active():
		hint_label.text = "当前地图不能使用自维修"
		return
	var submitted: bool = not multiplayer_presenter.request_use_ability(
		SELF_REPAIR_ABILITY_ID, player.position
	).is_empty()
	if submitted:
		hint_label.text = "已开始自维修：每3秒恢复一次生命"


## 在短促炮口动作结束后恢复开火前的移动状态。
## [param was_moving] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param layer_id] 本次开火临时切换动作的武器图层标识。
## 设计：等待期间若路线自然结束则恢复站立；仍在移动时从当前路径段重算朝向。
func _restore_locomotion_after_attack(was_moving: bool, layer_id: StringName) -> void:
	await get_tree().create_timer(0.16).timeout
	if player == null or not player.is_combat_actor_active():
		return
	player.clear_combat_layer_action(layer_id)
	if was_moving and local_player_controller.has_active_route():
		local_player_controller.refresh_route_direction()
	else:
		_set_player_action("stand")


## 执行 `handle_world_right_click` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：先在实际点击点播放原版反馈；图标锚点仅用于命中，不能替代可行走接近点。
func _handle_world_right_click(world_position: Vector2) -> void:
	movement_click_effects.present(world_position)
	var transition_view: Node2D = active_world_controller.transition_view_at(world_position)
	if transition_view != null:
		var transition: MapTransition = map_definition.transition_by_id(transition_view.transition_id)
		if transition != null and transition.kind == MapTransition.Kind.MULTI_CHOICE:
			_show_transition_choices(transition, world_position)
			return
		_move_to(transition_view.approach_point, transition_view.transition_id)
	else:
		_move_to(world_position)


## 执行 `move_to` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param transition_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _move_to(world_position: Vector2, transition_id: StringName = &"") -> void:
	if _world_input_locked():
		_stop_moving("地图切换中，暂时不能移动")
		return
	selected_transition_id = &""
	var target_text := "%d, %d" % [roundi(world_position.x), roundi(world_position.y)]
	var result: Dictionary = local_player_controller.request_move(world_position)
	if not bool(result.get("ok", false)):
		var error_code := StringName(result.get("code", &""))
		if error_code == &"movement.no_propulsion":
			var error_message := PlayerErrorMessages.describe(error_code)
			hint_label.text = error_message
			hud.show_system_message(error_message)
		elif error_code == &"no_reachable_point":
			hint_label.text = "目标 %s 不可到达，附近也没有可达点" % target_text
		else:
			hint_label.text = "无法找到前往 %s 的路径" % target_text
		return
	var resolved_position: Vector2 = result["resolved_position"]
	selected_transition_id = transition_id
	if bool(result["used_nearest_walkable"]):
		hint_label.text = "目标 %s 不可到达，正在前往附近 %d, %d" % [
			target_text,
			roundi(resolved_position.x),
			roundi(resolved_position.y),
		]
	else:
		hint_label.text = "正在前往 %s" % target_text
	hud.hide_popup()


## 执行 `begin_current_path_segment` 对应的模块操作。
func _begin_current_path_segment() -> void:
	if local_player_controller:
		local_player_controller.refresh_route_direction()


## 执行 `stop_moving` 对应的模块操作。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _stop_moving(message: String) -> void:
	if local_player_controller:
		local_player_controller.cancel_route()
	selected_transition_id = &""
	if hint_label:
		hint_label.text = message


## 执行 `direction_index` 对应的模块操作。
## [param motion] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _direction_index(motion: Vector2) -> int:
	return LocalPlayerControllerScript.direction_index(motion)


## 设置或恢复 `set_player_action` 对应的模块状态。
## [param action] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _set_player_action(action: String) -> void:
	if local_player_controller:
		local_player_controller.set_character_action(StringName(action))


## 执行 `sync_player_nodes` 对应的模块操作。
func _sync_player_nodes() -> void:
	if not player:
		return
	camera.position = player.position
	_update_minimap_dot()


## 创建共享玩家锚点，并同时准备人形与按地图切换的战车表现。
func _build_world() -> void:
	map_background = Sprite2D.new()
	map_background.name = "MapBase"
	map_background.centered = false
	map_background.position = Vector2.ZERO
	map_background.z_index = -100
	add_child(map_background)

	movement_click_effects = MovementClickEffectPresenterScript.new()
	movement_click_effects.name = "MovementClickEffects"
	movement_click_effects.z_index = -20
	add_child(movement_click_effects)

	sortable_world = Node2D.new()
	sortable_world.name = "YSortedWorld"
	sortable_world.y_sort_enabled = true
	add_child(sortable_world)

	player = PlayerWorldAvatarScript.new()
	player.name = "Player"
	var combat_manifest_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(COMBAT_VISUAL_MANIFEST_PATH)
	)
	var combat_manifest: Dictionary = {}
	if combat_manifest_value is Dictionary:
		combat_manifest = combat_manifest_value
	var avatar_error: Error = player.configure(
		CharacterFactoryScript.build_character_set(character_catalog, "player"),
		combat_manifest,
		"H番茄花园",
		Color(0.35, 1.0, 0.92),
		PlayerWorldAvatarScript.HUMAN_NAME_LABEL_POSITION,
	)
	if avatar_error != OK:
		push_error("Unable to configure player avatar: %s" % error_string(avatar_error))
	player.set_animation_speed_scale(player_animation_speed_scale)
	sortable_world.add_child(player)

	for mode_id: String in WEAPON_MODES:
		var mode: Dictionary = WEAPON_MODES[mode_id]
		var controller := WeaponAttackVisualControllerScript.new()
		controller.name = "%sAttackVisualController" % mode_id.to_pascal_case()
		add_child(controller)
		var attack_visual_error: Error = controller.configure(
			combat_manifest, sortable_world, StringName(mode["weapon_id"])
		)
		if attack_visual_error != OK:
			push_error("Unable to configure %s visuals: %s" % [
				mode_id, error_string(attack_visual_error),
			])
			controller.free()
			continue
		combat_attack_controllers[mode_id] = controller
	combat_attack_controller = combat_attack_controllers.get("energy_cannon")
	monster_world_controller = MonsterWorldControllerScript.new()
	monster_world_controller.name = "MonsterWorldController"
	add_child(monster_world_controller)
	var monster_error := monster_world_controller.configure(sortable_world, combat_manifest, player)
	if monster_error != OK:
		push_error("Unable to configure monster world presentation: %s" % error_string(monster_error))
	else:
		for controller: Node in combat_attack_controllers.values():
			controller.set_visual_collision_resolver(monster_world_controller.first_visual_collision)
	item_catalog = ItemCatalogScript.new()
	var item_catalog_result := item_catalog.initialize()
	if item_catalog_result.is_ok:
		ground_loot_world_controller = GroundLootWorldControllerScript.new()
		ground_loot_world_controller.name = "GroundLootWorldController"
		add_child(ground_loot_world_controller)
		var loot_error := ground_loot_world_controller.configure(
			sortable_world,
			item_catalog,
		)
		if loot_error != OK:
			push_error("Unable to configure ground loot presentation: %s" % error_string(loot_error))
	else:
		push_error("Unable to load shared item catalog: %s" % item_catalog_result.error_message)
	var mining_manifest_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(MINING_VISUAL_MANIFEST_PATH)
	)
	if mining_manifest_value is Dictionary:
		mineral_world_controller = MineralWorldControllerScript.new()
		mineral_world_controller.name = "MineralWorldController"
		add_child(mineral_world_controller)
		var mining_error := mineral_world_controller.configure(
			sortable_world,
			mining_manifest_value,
		)
		if mining_error != OK:
			push_error("Unable to configure mineral presentation: %s" % error_string(mining_error))
	else:
		push_error("Unable to load mineral presentation manifest")

	local_player_controller = LocalPlayerControllerScript.new()
	local_player_controller.name = "LocalPlayerController"
	add_child(local_player_controller)
	var controller_error: Error = local_player_controller.configure(
		player,
		DiamondNavigationScript.new(),
		player_movement_speed,
		Vector2.ZERO,
	)
	if controller_error != OK:
		push_error("Unable to configure local player controller: %s" % error_string(controller_error))

	camera = Camera2D.new()
	camera.name = "PlayerCamera"
	camera.position = player.position
	# 原客户端按 ALE 与地图像素 1:1 绘制；窗口变大只扩大视野，不缩放世界内容。
	camera.zoom = Vector2.ONE
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = 0
	camera.limit_bottom = 0
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.5
	add_child(camera)
	camera.make_current()
	local_player_controller.position_changed.connect(_on_local_player_position_changed)
	local_player_controller.route_finished.connect(_on_local_player_route_finished)
	local_player_controller.route_stopped.connect(_on_local_player_route_stopped)


## 执行 `build_hud` 对应的模块操作。
## [param initial_bundle] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _build_hud(initial_bundle: Dictionary) -> void:
	var initial_definition: MapDefinition = initial_bundle["definition"]
	var initial_resources: Dictionary = initial_bundle["resources"]
	hud = HallHudScript.new()
	hud.configure(
		initial_definition.world_size,
		initial_resources["minimap"],
		String(initial_definition.display_name),
	)
	add_child(hud)
	hint_label = hud.hint_label
	popup = hud.popup
	minimap_player_dot = hud.minimap_player_dot
	hud.popup_closed.connect(_on_npc_popup_closed)
	hud.npc_action_requested.connect(_on_npc_action_requested)
	hud.hud_action_requested.connect(_on_hud_action_requested)
	hud.state.selected_action_slot_changed.connect(_on_weapon_slot_selected)
	_on_weapon_slot_selected(hud.state.selected_action_slot)
	vehicle_destroyed_dialog = VehicleDestroyedDialogScript.new()
	vehicle_destroyed_dialog.configure()
	vehicle_destroyed_dialog.wait_selected.connect(_on_destroyed_wait_selected)
	vehicle_destroyed_dialog.return_to_base_requested.connect(_request_vehicle_recovery)
	hud.root_control.add_child(vehicle_destroyed_dialog)


## 创建大厅客户端会话表现器，并以显式配置选择离线调试或真实网络入口。
## 设计：大厅保留输入、导航与动画职责；表现器仅将预测/权威状态投影到角色节点。
func _build_multiplayer_presentation() -> void:
	mining_visual_controller.configure(player)
	self_repair_visual_controller = SelfRepairVisualControllerScript.new()
	self_repair_visual_controller.name = "SelfRepairVisualController"
	add_child(self_repair_visual_controller)
	var repair_visual_error := self_repair_visual_controller.configure(player)
	if repair_visual_error != OK:
		push_error("Unable to configure self-repair presentation: %s" % error_string(repair_visual_error))

	map_preloader = ClientMapPreloaderScript.new()
	map_preloader.name = "ClientMapPreloader"
	var map_definition_paths := _load_map_directory_definitions()
	map_preloader.configure(map_definition_paths)
	map_preloader.map_preload_ready.connect(_on_map_preload_ready)
	map_preloader.map_preload_failed.connect(_on_map_preload_failed)
	add_child(map_preloader)
	map_route_resolver = RuntimeMapRouteResolverScript.new()
	if not map_route_resolver.configure(map_definition_paths):
		push_error("Unable to configure runtime map routes: %s" % "; ".join(
			map_route_resolver.errors
		))

	multiplayer_presenter = HallMultiplayerPresenterScript.new()
	multiplayer_presenter.name = "HallMultiplayerPresenter"
	multiplayer_presenter.configure(player, sortable_world, character_catalog, hint_label)
	multiplayer_presenter.local_character_state_applied.connect(
		_on_multiplayer_local_character_state_applied
	)
	multiplayer_presenter.map_joined.connect(_on_authoritative_map_joined)
	multiplayer_presenter.connection_failed.connect(_on_initial_connection_failed)
	multiplayer_presenter.map_change_failed.connect(_on_authoritative_map_change_failed)
	multiplayer_presenter.combat_snapshot_received.connect(_on_combat_snapshot_received)
	multiplayer_presenter.combat_event_received.connect(_on_combat_event_received)
	multiplayer_presenter.vehicle_recovery_scheduled.connect(
		_on_vehicle_recovery_scheduled
	)
	multiplayer_presenter.vehicle_recovery_failed.connect(_on_vehicle_recovery_failed)
	multiplayer_presenter.system_message_requested.connect(hud.show_system_message)
	add_child(multiplayer_presenter)
	var start_error: Error = multiplayer_presenter.start({
		"offline_debug_enabled": multiplayer_offline_debug_enabled,
		"connect_automatically": multiplayer_connect_automatically,
		"server_host": multiplayer_server_host,
		"server_port": multiplayer_server_port,
		"local_entity_id": multiplayer_local_entity_id,
		"map_id": map_definition.map_id,
		"map_instance_id": multiplayer_map_instance_id,
		"initial_position": player.position,
		"remote_appearance": "player",
		"remote_animation_speed_scale": player_animation_speed_scale,
	})
	if start_error != OK:
		push_warning("Unable to start hall multiplayer presentation: %s" % error_string(start_error))
		_on_initial_connection_failed(error_string(start_error))
	local_player_controller.set_multiplayer_presenter(multiplayer_presenter)
	_build_game_windows()


## 创建人物、背包和战车单例窗口并接入唯一客户端会话。
## 设计：窗口不知道底层是 ENet 还是进程内传输，只消费相同的权威面板消息。
func _build_game_windows() -> void:
	game_window_manager = GameWindowManagerScript.new()
	game_window_manager.name = "GameWindowManager"
	hud.root_control.add_child(game_window_manager)
	game_window_manager.notice_requested.connect(hud.show_system_message)
	panel_session = PlayerPanelSession.new(
		Callable(multiplayer_presenter, "request_player_panel_command"),
		item_catalog,
	)
	multiplayer_presenter.player_panel_bundle_received.connect(
		panel_session.apply_bundle
	)
	panel_session.player_changed.connect(_on_current_player_changed)
	game_window_manager.configure(panel_session)
	multiplayer_presenter.skill_level_up_received.connect(_on_skill_level_up)


## 将线上或离线权威升级事件格式化为荣耀版原句式并交给 HUD 排队。
## [param event] 含 skill_id 与 new_level 的权威升级事件。
func _on_skill_level_up(event: Dictionary) -> void:
	if hud == null:
		return
	hud.show_system_message(SkillLevelMessageFormatter.format(
		String(event.get("skill_id", "")), int(event.get("new_level", 0))
	))


## 将客户端唯一 CurrentPlayer 的服装对象同步到世界人物表现。
## [param current_player] 刚应用同事务权威快照的当前玩家聚合。
func _on_current_player_changed(current_player: Player) -> void:
	if player != null:
		player.apply_character_equipment(
			current_player.character_equipment,
			character_catalog,
		)
		player.apply_vehicle_equipment(current_player.vehicle)
	if hud != null:
		var primary_device: VehicleEquipment = current_player.vehicle.loadout.at(1)
		hud.set_primary_device("" if primary_device == null else primary_device.primary_device_kind())
		var tactical_equipment: VehicleEquipment = current_player.vehicle.loadout.at(13)
		var action_id := "" if tactical_equipment == null else String(
			TACTICAL_ACTION_BY_DEFINITION.get(tactical_equipment.definition_id, "")
		)
		hud.set_tactical_action(action_id)
	_refresh_local_movement_availability(current_player)


## 根据活动地图与权威玩家装配刷新本地预测移动许可。
## 室内始终按人物移动；野外必须存在提供正推进力的引擎。
## [param current_player] 最新玩家聚合；为空时从当前面板投影读取。
func _refresh_local_movement_availability(current_player: Player = null) -> void:
	if local_player_controller == null or map_definition == null:
		return
	var player_state := current_player
	if player_state == null and game_window_manager != null:
		player_state = panel_session.current_player
	var movement_enabled := true
	if map_definition.category == "field":
		movement_enabled = player_state != null \
			and int(player_state.calculate_vehicle_stats().get("propulsion", 0)) > 0
	local_player_controller.set_movement_enabled(movement_enabled)


## 读取受控地图目录的 `definitions` 映射，格式错误时返回仅包含当前大厅的安全目录。
## 返回该函数计算、查询或操作得到的结果。
## 设计：网络消息不能提供资源路径；所有预载目标必须先存在于版本化目录。
func _load_map_directory_definitions() -> Dictionary:
	var fallback := {StringName(map_definition.map_id): MAP_DEFINITION_PATH}
	if not FileAccess.file_exists(MAP_DIRECTORY_PATH):
		return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_DIRECTORY_PATH))
	if not parsed is Dictionary or not parsed.get("definitions", {}) is Dictionary:
		return fallback
	return parsed["definitions"].duplicate(true)


## 处理 `_on_multiplayer_local_character_state_applied` 对应的信号回调。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_multiplayer_local_character_state_applied(state: Dictionary) -> void:
	local_player_controller.apply_authoritative_presentation(state)


## 处理 `_on_local_player_position_changed` 对应的信号回调。
## [param _position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_local_player_position_changed(_position: Vector2) -> void:
	_sync_player_nodes()


## 在本地路线自然完成后检查脚点附近是否存在地图出口。
func _on_local_player_route_finished() -> void:
	_try_begin_nearby_map_transition()


## 处理 `_on_local_player_route_stopped` 对应的信号回调。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_local_player_route_stopped(message: String) -> void:
	selected_transition_id = &""
	if hint_label:
		hint_label.text = message


## 在活动世界原子替换前结束旧 NPC 交互，并清除仅属于旧地图的传送选择。
func _on_active_world_will_replace() -> void:
	if active_npc and is_instance_valid(active_npc):
		active_npc.set_interaction_active(false)
	active_npc = null
	selected_transition_id = &""
	transition_choice_ids.clear()
	if movement_click_effects != null:
		movement_click_effects.clear_effects()
	for controller: Node in combat_attack_controllers.values():
		controller.clear_effects()
	if monster_world_controller != null:
		monster_world_controller.clear()
	if mineral_world_controller != null:
		mineral_world_controller.clear()
	mining_visual_controller.clear()


## 在玩家停步后查找触发半径内最近的内部出口，并先预载其目标地图。
## 设计：客户端只从受控本地定义取得目标内容；真正的地图和落点仍由服务端裁决。
func _try_begin_nearby_map_transition() -> void:
	if not pending_map_transition.is_empty() or map_preloader == null:
		return
	var selected_transition: MapTransition
	var selected_destination_map_id: StringName = &""
	var selected_distance := map_transition_trigger_radius
	if not selected_transition_id.is_empty():
		var requested_transition: MapTransition = map_definition.transition_by_id(selected_transition_id)
		if requested_transition != null:
			var requested_destination_map_id := _resolve_transition_destination_id(
				requested_transition
			)
			if requested_destination_map_id.is_empty():
				selected_transition_id = &""
				hint_label.text = "地图%s已识别，但运行资源尚未导入" % [
					requested_transition.destination_key().to_upper(),
				]
				return
			var requested_distance := player.position.distance_to(requested_transition.approach_point)
			if requested_distance <= selected_distance:
				selected_transition = requested_transition
				selected_destination_map_id = requested_destination_map_id
				selected_distance = requested_distance
	else:
		for transition: MapTransition in map_definition.enabled_transitions():
			var destination_map_id := _resolve_transition_destination_id(transition)
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
	hint_label.text = "正在准备前往%s…" % selected_transition.label
	var preload_error: Error = map_preloader.preload_map(
		selected_destination_map_id
	)
	if preload_error != OK and not pending_map_transition.is_empty():
		pending_map_transition.clear()


## 使用与权威服务器相同的世界内旧代码规则解析预载目标，但仅返回受控内容目录中的地图。
## [param transition] 当前活动地图内待解析的出口。
## 返回允许客户端预载的运行时地图 ID；未导入目标返回空值。
func _resolve_transition_destination_id(transition: MapTransition) -> StringName:
	if map_route_resolver != null:
		return map_route_resolver.resolve_target_id(transition, map_definition.world_id)
	return transition.destination_map_id


## 处理 `_on_map_preload_ready` 对应的信号回调。
## [param map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param bundle] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_map_preload_ready(map_id: StringName, bundle: Dictionary) -> void:
	if (
		not pending_authoritative_join.is_empty()
		and StringName(pending_authoritative_join.get("map_id", &"")) == map_id
	):
		var join := pending_authoritative_join.duplicate(true)
		pending_authoritative_join.clear()
		var joined_spawn_position: Vector2 = join["spawn_position"]
		if not _commit_map_bundle(bundle, joined_spawn_position, String(join["map_instance_id"])):
			_handle_map_commit_failure("权威地图资源提交失败")
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
		hint_label.text = "当前无法提交地图切换请求"
		pending_map_transition.clear()
		pending_map_bundle.clear()


## 处理 `_on_map_preload_failed` 对应的信号回调。
## [param map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_map_preload_failed(map_id: StringName, message: String) -> void:
	push_warning("Map preload failed [%s]: %s" % [map_id, message])
	var notice := PlayerErrorMessages.describe(&"map.load_failed")
	if not pending_authoritative_join.is_empty():
		pending_authoritative_join.clear()
		_handle_map_commit_failure(notice)
		return
	hint_label.text = notice
	pending_map_transition.clear()
	pending_map_bundle.clear()


## 处理 `_on_authoritative_map_joined` 对应的信号回调。
## [param map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param spawn_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param _definition_version] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_authoritative_map_joined(
	map_id: StringName,
	map_instance_id: String,
	spawn_position: Vector2,
	_definition_version: int,
) -> void:
	if map_definition.map_id == map_id:
		_stop_moving("正在载入权威地图…")
		map_commit_failure_locked = false
		multiplayer_map_instance_id = map_instance_id
		local_player_controller.set_position(spawn_position)
		_stop_moving("已进入%s" % map_definition.display_name)
		pending_map_transition.clear()
		pending_map_bundle.clear()
		_finish_initial_loading()
		return
	if (
		not pending_map_bundle.is_empty()
		and pending_map_bundle["definition"].map_id == map_id
	):
		if not _commit_map_bundle(pending_map_bundle, spawn_position, map_instance_id):
			_handle_map_commit_failure("权威地图资源提交失败")
		return
	_hold_old_map_for_authoritative_join(map_id, map_instance_id, spawn_position)
	var preload_error: Error = map_preloader.preload_map(map_id)
	if preload_error != OK and not pending_authoritative_join.is_empty():
		_handle_map_commit_failure("客户端缺少权威地图资源")


## 执行 `hold_old_map_for_authoritative_join` 对应的模块操作。
## [param map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param spawn_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：立即终止旧路径；新出生点由 session 持有，但旧场景直到 bundle 提交前不呈现它。
func _hold_old_map_for_authoritative_join(
	map_id: StringName,
	map_instance_id: String,
	spawn_position: Vector2,
) -> void:
	var held_player_position: Vector2 = local_player_controller.position()
	local_player_controller.hold_position_for_map_commit()
	hint_label.text = "正在载入权威地图…"
	pending_authoritative_join = {
		"map_id": map_id,
		"map_instance_id": map_instance_id,
		"spawn_position": spawn_position,
		"held_player_position": held_player_position,
	}


## 在权威切图拒绝时清空对应预载包；旧地图画面和导航保持不变。
## [param _transition_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param _code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param _message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_authoritative_map_change_failed(
	_transition_id: StringName,
	_code: StringName,
	_message: String,
) -> void:
	pending_map_transition.clear()
	pending_map_bundle.clear()
	pending_authoritative_join.clear()


## 执行 `commit_map_bundle` 对应的模块操作。
## [param bundle] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param spawn_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：所有可失败加载均先暂存，当前场景直到验证完成才被清理。
func _commit_map_bundle(
	bundle: Dictionary,
	spawn_position: Vector2,
	map_instance_id: String,
) -> bool:
	if not active_world_controller.commit_bundle(bundle, spawn_position):
		return false
	_refresh_local_movement_availability()
	multiplayer_map_instance_id = map_instance_id
	_set_player_action("stand")
	hint_label.text = "已进入%s" % map_definition.display_name
	map_commit_failure_locked = false
	pending_map_transition.clear()
	pending_map_bundle.clear()
	_finish_initial_loading()
	return true


## 处理 `_on_combat_snapshot_received` 对应的信号回调。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_combat_snapshot_received(snapshot: Dictionary) -> void:
	mining_visual_controller.apply_snapshot(snapshot)
	for mode_id: String in combat_attack_controllers:
		var mode: Dictionary = WEAPON_MODES[mode_id]
		combat_attack_controllers[mode_id].apply_authoritative_snapshot(snapshot, String(mode["ability_id"]))
	monster_world_controller.apply_snapshot(snapshot)
	if ground_loot_world_controller != null:
		ground_loot_world_controller.apply_snapshot(snapshot)
	if mineral_world_controller != null:
		mineral_world_controller.apply_snapshot(snapshot)
	var vehicle: Variant = snapshot.get("local_vehicle", {})
	if vehicle is Dictionary:
		player.set_combat_status(vehicle)
		hud.set_vehicle_combat_state(vehicle)
		# 非战斗地图仍同步战车资源供 HUD/面板消费，但人物移动不受停放战车生命值影响。
		var combat_vehicle_active := bool(
			snapshot.get("vehicle_combat_active", player.is_combat_actor_active())
		)
		var destroyed := combat_vehicle_active and int(vehicle.get("health", 0)) <= 0
		player.set_vehicle_destroyed(destroyed)
		if destroyed and not _vehicle_destroyed:
			_vehicle_destroyed = true
			_stop_moving("战车已被击毁")
			vehicle_destroyed_dialog.show_destroyed()
		elif not destroyed and _vehicle_destroyed:
			_vehicle_destroyed = false
			vehicle_destroyed_dialog.hide_dialog()
		if self_repair_visual_controller != null:
			self_repair_visual_controller.apply_snapshot(vehicle)


## 提交击毁后的回基地选择；目的地图、三秒等待和回血比例均由服务器决定。
func _request_vehicle_recovery() -> void:
	if not _vehicle_destroyed or multiplayer_presenter == null:
		return
	if multiplayer_presenter.request_vehicle_recovery().is_empty():
		vehicle_destroyed_dialog.show_recovery_failed("基地救援请求发送失败")


## 显示服务器确认的基地救援等待时间。
## [param delay_seconds] 调用方传入的 `delay_seconds` 参数。
func _on_vehicle_recovery_scheduled(delay_seconds: float) -> void:
	vehicle_destroyed_dialog.show_recovery_scheduled(delay_seconds)


## 恢复被服务器拒绝的死亡窗选择。
## [param _code] 调用方传入的 `_code` 参数。
## [param _message] 调用方传入的 `_message` 参数。
func _on_vehicle_recovery_failed(_code: StringName, _message: String) -> void:
	vehicle_destroyed_dialog.show_recovery_failed("基地救援请求被拒绝，请重试")


## 原地等待只关闭选择窗，不解除击毁状态或恢复输入。
func _on_destroyed_wait_selected() -> void:
	hint_label.text = "正在原地等待其他玩家营救"


## 处理 `_on_combat_event_received` 对应的信号回调。
## [param event] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_combat_event_received(event: Dictionary) -> void:
	var event_type := StringName(event.get("event_type", ""))
	if event_type == &"loot_picked_up":
		if ground_loot_world_controller != null:
			ground_loot_world_controller.remove_loot(String(event.get("loot_id", "")))
		hint_label.text = "拾取了 %d 个物品" % int(event.get("quantity", 1))
	elif event_type == &"mining_started":
		hint_label.text = "开始采矿，每3秒采集一次"
	elif event_type == &"mining_collected":
		hint_label.text = "采集到%s × %d（矿点剩余%d）" % [
			String(event.get("display_name", "矿物")),
			int(event.get("quantity", 1)),
			int(event.get("remaining", 0)),
		]
	elif event_type in [&"energy_cannon_hit", &"rocket_launcher_hit", &"missile_hit"]:
		hint_label.text = "命中目标，造成%d点伤害（剩余%d）" % [
			int(event.get("damage", 0)),
			int(event.get("target_health", 0)),
		]
	elif event_type == &"self_repair_resolved":
		hint_label.text = "自维修恢复%d点生命（当前%d）" % [
			int(event.get("healed", 0)),
			int(event.get("target_health", 0)),
		]
	elif event_type == &"self_repair_stopped":
		var reason := StringName(event.get("reason", &""))
		hint_label.text = "战车已修复完成" if reason == &"full_health" else "自维修已停止"


## 执行 `handle_map_commit_failure` 对应的模块操作。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _handle_map_commit_failure(message: String) -> void:
	push_warning("Map commit failed: %s" % message)
	var notice := PlayerErrorMessages.describe(&"map.load_failed", message)
	map_commit_failure_locked = true
	_stop_moving(notice)
	if not _initial_authoritative_world_ready and initial_loading_screen != null:
		initial_loading_screen.set_status(notice)
	pending_map_transition.clear()
	pending_map_bundle.clear()
	pending_authoritative_join.clear()
	if multiplayer_presenter:
		multiplayer_presenter.stop()


## 报告旧地图世界输入是否必须暂停，直到切图完成、失败回滚或会话被安全关闭。
## 返回该函数计算、查询或操作得到的结果。
## 设计：闸门只冻结本地世界交互；服务端拒绝会清空 pending 并恢复旧地图输入。
func _world_input_locked() -> bool:
	if map_commit_failure_locked:
		return true
	if _vehicle_destroyed:
		return true
	if (
		not pending_map_transition.is_empty()
		or not pending_authoritative_join.is_empty()
	):
		return true
	if multiplayer_presenter == null or multiplayer_presenter.session == null:
		return false
	return multiplayer_presenter.session.is_map_change_pending()


## 查找鼠标点命中的最近 NPC 或生产设施。
## [param world_position] 鼠标对应的地图世界坐标。
## [param maximum_distance] NPC 默认点选距离；设施使用各自配置的命中半径。
## 返回最近的可交互节点；没有命中时返回 null。
func _nearest_npc(world_position: Vector2, maximum_distance: float) -> Node2D:
	var result: Node2D
	var closest_distance := INF
	for npc in npc_instances:
		var distance := npc.position.distance_to(world_position)
		if distance <= maximum_distance and distance < closest_distance:
			closest_distance = distance
			result = npc
	for facility in facility_instances:
		var distance := facility.position.distance_to(world_position)
		if facility.hit_test(world_position) and distance < closest_distance:
			closest_distance = distance
			result = facility
	return result


## 执行 `show_npc_popup` 对应的模块操作。
## [param npc] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _show_npc_popup(npc: Node2D) -> void:
	_stop_moving("正在与%s交互" % String(npc.get_interaction_data()["title"]))
	if active_npc and active_npc != npc:
		active_npc.set_interaction_active(false)
	active_npc = npc
	active_npc.set_interaction_active(true)
	var screen_position := get_viewport().get_canvas_transform() * active_npc.global_position
	hud.show_npc_popup(active_npc.get_interaction_data(), screen_position)


## 处理 `_on_npc_popup_closed` 对应的信号回调。
func _on_npc_popup_closed() -> void:
	if active_npc:
		active_npc.set_interaction_active(false)
		active_npc = null


## 将交互菜单动作分派到传送、制造、商店或 NPC 业务处理器。
## [param action_id] 当前菜单发出的业务动作标识。
## 设计：关闭菜单会同步清空 active_npc，窗口所需的标识和标题必须在关闭前读取。
func _on_npc_action_requested(action_id: String) -> void:
	if transition_choice_ids.has(action_id):
		var transition_id := StringName(transition_choice_ids[action_id])
		var transition: MapTransition = map_definition.transition_by_id(transition_id)
		transition_choice_ids.clear()
		hud.hide_popup()
		if transition != null:
			_move_to(transition.approach_point, transition.transition_id)
		return
	if is_instance_valid(active_npc):
		var interaction_title := String(active_npc.get_interaction_data()["title"])
		if action_id == "manufacture" and active_npc is WorldFacilityInteraction:
			var station_id := (active_npc as WorldFacilityInteraction).station_id
			if station_id.is_empty():
				return
			hud.hide_popup()
			game_window_manager.open_manufacturing(station_id)
			hint_label.text = "正在使用%s" % interaction_title
			return
		var npc_id := String(active_npc.get("npc_id"))
		var npc_definition: Variant = active_npc.get("npc_definition")
		var interaction_service := String(npc_definition.get("interaction_service", "")) \
			if npc_definition is Dictionary else ""
		if interaction_service == "commerce" \
				and action_id in ["buy", "sell", "task"]:
			hud.hide_popup()
			game_window_manager.open_weapon_merchant(action_id, npc_id)
			hint_label.text = "正在与%s交互" % interaction_title
			return
		hint_label.text = active_npc.handle_action(action_id)


## 显示同一原版 transport2 锚点的目标选择菜单。
## [param selected] 鼠标命中的任一多目标传送定义。
## [param world_position] 右键点击的地图世界坐标。
## 设计：选择只决定 transition_id；寻路、预载和最终切图仍走既有权威传送链。
func _show_transition_choices(selected: MapTransition, world_position: Vector2) -> void:
	transition_choice_ids.clear()
	var actions: Array[Dictionary] = []
	for transition: MapTransition in map_definition.enabled_transitions():
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
func _on_hud_action_requested(action_id: String) -> void:
	if action_id == "friends":
		hud.show_system_message("好友列表暂未实现")
		return
	if action_id == "return_base" and _vehicle_destroyed:
		_request_vehicle_recovery()
		return
	if action_id == SELF_REPAIR_ABILITY_ID:
		_request_self_repair()
		return
	if game_window_manager != null and game_window_manager.toggle(action_id):
		return


## 响应底栏武器槽选择并切换玩家战车的可见武器图层。
## [param slot_id] 被选中的底栏武器槽标识。
func _on_weapon_slot_selected(slot_id: String) -> void:
	var mode: Dictionary = WEAPON_MODES.get(slot_id, {})
	if player != null and not mode.is_empty():
		player.set_combat_weapon_layer(StringName(mode["layer_id"]))


## 推进并更新 `update_minimap_dot` 对应的模块状态。
func _update_minimap_dot() -> void:
	if hud and player:
		hud.update_player_dot(player.position)


# Diagnostic compatibility wrappers keep map tests focused on behavior while
# the implementation lives in DiamondNavigation.
## 执行 `world_to_cell` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _world_to_cell(world_position: Vector2) -> Vector2i:
	return navigation.world_to_cell(world_position)


## 执行 `cell_to_world` 对应的模块操作。
## [param cell] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _cell_to_world(cell: Vector2i) -> Vector2:
	return navigation.cell_to_world(cell)


## 执行 `cell_id` 对应的模块操作。
## [param cell] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _cell_id(cell: Vector2i) -> int:
	return navigation.cell_id(cell)


## 执行 `raw_cell_walkable` 对应的模块操作。
## [param cell] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _raw_cell_walkable(cell: Vector2i) -> bool:
	return navigation.raw_cell_walkable(cell)


## 判断 `is_walkable` 对应的模块状态。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _is_walkable(world_position: Vector2) -> bool:
	return navigation.is_walkable(world_position)


## 执行 `simplify_path` 对应的模块操作。
## [param raw_path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _simplify_path(raw_path: PackedVector2Array) -> PackedVector2Array:
	return navigation.simplify_path(raw_path)


## 执行 `segment_is_walkable` 对应的模块操作。
## [param from_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param to_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _segment_is_walkable(from_position: Vector2, to_position: Vector2) -> bool:
	return navigation.segment_is_walkable(from_position, to_position)
