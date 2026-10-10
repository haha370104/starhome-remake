class_name HallMultiplayerPresenter
extends Node

signal local_character_state_applied(state: Dictionary)
signal remote_character_added(entity_id: StringName, character: Node2D)
signal remote_character_removed(entity_id: StringName)
signal map_change_requested(transition_id: StringName, transition_sequence: int)
signal map_joined(
	map_id: StringName,
	map_instance_id: String,
	spawn_position: Vector2,
	definition_version: int,
)
signal map_change_failed(transition_id: StringName, code: StringName, message: String)
signal combat_snapshot_received(snapshot: Dictionary)
signal combat_event_received(event: Dictionary)
signal player_panel_bundle_received(bundle: Dictionary)
signal social_event_received(message: Dictionary)
signal skill_level_up_received(event: Dictionary)
signal vehicle_recovery_scheduled(delay_seconds: float)
signal vehicle_recovery_failed(code: StringName, message: String)
signal connection_failed(message: String)
signal system_message_requested(message: String)
signal network_notice_requested(message: String, duration_seconds: float)
signal command_rejected(code: StringName, message: String)

const SessionScript := preload("res://scripts/client/network/client_multiplayer_session.gd")
const CharacterFactoryScript := preload("res://scripts/characters/character_factory.gd")
const PlayerWorldAvatarScript := preload("res://scripts/characters/player_world_avatar.gd")

signal synchronization_started(sync_id: String)
signal player_change_received(change: Dictionary)

var session: ClientMultiplayerSession
var remote_characters: Dictionary = {}
var last_connection_error_message := ""

var _local_character: PlayerWorldAvatar
var _remote_parent: Node2D
var _character_catalog: Dictionary = {}
var _item_catalog: ItemCatalog
var _remote_appearance_key := "player"
var _remote_animation_speed_scale := 1.0


## 绑定本地角色和远端角色渲染依赖；状态提示通过业务信号交给 HUD。
## [param local_character] 接收本地会话表现的玩家锚点。
## [param remote_parent] 远端角色视图所在的世界排序层。
## [param character_catalog] 已加载的角色动画与外观目录。
## 设计：表现器只投影会话状态，不拥有路径规划、输入采样或传输协议。
func configure(
	local_character: PlayerWorldAvatar,
	remote_parent: Node2D,
	character_catalog: Dictionary,
	item_catalog: ItemCatalog,
) -> void:
	_local_character = local_character
	_remote_parent = remote_parent
	_character_catalog = character_catalog
	_item_catalog = item_catalog


## 执行 `start` 对应的模块操作。
## [param settings] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：`offline_debug_enabled` 必须由调用方显式提供；缺省值始终选择真实网络边界。
func start(settings: Dictionary) -> Error:
	last_connection_error_message = ""
	if session != null:
		return ERR_ALREADY_IN_USE
	if _local_character == null or _remote_parent == null or _character_catalog.is_empty() or _item_catalog == null:
		return ERR_UNCONFIGURED
	if not settings.has("offline_debug_enabled"):
		return ERR_INVALID_PARAMETER

	_remote_appearance_key = String(settings.get("remote_appearance", "player"))
	_remote_animation_speed_scale = float(settings.get("remote_animation_speed_scale", 1.0))

	session = SessionScript.new()
	session.name = "ClientMultiplayerSession"
	session.offline_debug_enabled = bool(settings["offline_debug_enabled"])
	session.local_entity_id = StringName(settings.get("local_entity_id", &"player.local"))
	session.local_display_name = String(settings.get("local_display_name", ""))
	session.current_map_id = StringName(settings.get("map_id", &""))
	session.current_map_instance_id = String(settings.get("map_instance_id", ""))
	session.connection_state_changed.connect(_on_connection_state_changed)
	session.connection_failed.connect(_on_connection_failed)
	session.command_rejected.connect(_on_command_rejected)
	session.local_presentation_state_changed.connect(_on_local_presentation_state_changed)
	session.remote_presentation_state_changed.connect(_on_remote_presentation_state_changed)
	session.remote_entity_removed.connect(_on_remote_entity_removed)
	session.map_change_requested.connect(map_change_requested.emit)
	session.map_joined.connect(map_joined.emit)
	session.map_change_failed.connect(_on_map_change_failed)
	session.combat_snapshot_received.connect(combat_snapshot_received.emit)
	session.combat_event_received.connect(combat_event_received.emit)
	session.loot_picked_up.connect(_on_loot_picked_up)
	session.player_change_received.connect(player_change_received.emit)
	session.synchronization_started.connect(synchronization_started.emit)
	session.mining_collected.connect(_on_mining_collected)
	session.player_panel_bundle_received.connect(player_panel_bundle_received.emit)
	session.social_event_received.connect(social_event_received.emit)
	session.skill_level_up_received.connect(skill_level_up_received.emit)
	session.vehicle_recovery_scheduled.connect(vehicle_recovery_scheduled.emit)
	session.vehicle_recovery_failed.connect(vehicle_recovery_failed.emit)
	add_child(session)
	session.initialize_local_player(Vector2(settings.get("initial_position", _local_character.position)))

	if not bool(settings.get("connect_automatically", true)):
		network_notice_requested.emit("权威会话尚未连接", 1.5)
		return OK
	var host := String(settings.get("server_host", "127.0.0.1"))
	var port := int(settings.get("server_port", ClientNetworkAdapter.DEFAULT_PORT))
	var connection_error := session.connect_to_server(host, port)
	if connection_error != OK:
		network_notice_requested.emit("连接失败：%s" % error_string(connection_error), 4.0)
	elif session.offline_debug_enabled:
		network_notice_requested.emit("正在启动进程内权威服务器…", 1.5)
	return connection_error


## 主动断开会话并移除全部远端角色表现节点。
func stop() -> void:
	if session != null:
		session.disconnect_from_server()
	for entity_id in remote_characters.keys():
		_remove_remote_character(StringName(entity_id))


## 执行 `request_move` 对应的模块操作。
## [param requested_world_point] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：表现器不自行裁剪目标点；调用方应先完成本地导航约束解析。
func request_move(requested_world_point: Vector2) -> Dictionary:
	if session == null:
		return {}
	return session.request_move(requested_world_point)


## 执行 `request_use_ability` 对应的模块操作。
## [param ability_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param aim_world_position] 瞄准世界坐标，只用于表达发射方向。
## 返回该函数计算、查询或操作得到的结果。
func request_use_ability(ability_id: String, aim_world_position: Vector2) -> Dictionary:
	if session == null:
		return {}
	return session.request_use_ability(ability_id, aim_world_position)


## 将击毁后回基地的选择交给客户端会话与权威服务器。
## 返回该函数计算、查询或操作得到的结果。
func request_vehicle_recovery() -> Dictionary:
	if session == null:
		return {}
	return session.request_vehicle_recovery()


## 将地面掉落拾取意图转交客户端会话。
## [param loot_id] 权威快照发布的掉落实例标识。
## 返回已发送的最小载荷；会话未建立时返回空字典。
func request_loot_pickup(loot_id: String) -> Dictionary:
	if session == null:
		return {}
	return session.request_loot_pickup(loot_id)


## 将面板操作意图转交客户端会话。
## [param command] 查询、移动、整理、穿装或卸装命令。
## 返回已发送载荷；会话未建立时返回空字典。
func request_player_panel_command(command: Dictionary) -> Dictionary:
	if session == null:
		return {}
	return session.request_player_panel_command(command)


## 将社交意图转交同一权威会话。
func request_social_command(command: Dictionary) -> Dictionary:
	if session == null:
		return {}
	return session.request_social_command(command)


## 执行 `request_map_change` 对应的模块操作。
## [param transition_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param destination_entry_number] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func request_map_change(
	transition_id: StringName,
	destination_entry_number: int = 0,
) -> Dictionary:
	if session == null:
		return {}
	return session.request_map_change(transition_id, destination_entry_number)


## 执行 `record_local_predicted_delta` 对应的模块操作。
## [param input_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param displacement] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：权威校正仍由 `ClientMultiplayerSession` 处理，场景不得直接写校正坐标。
func record_local_predicted_delta(input_sequence: int, displacement: Vector2) -> bool:
	if session == null or input_sequence <= 0 or displacement.is_zero_approx():
		return false
	return session.record_local_predicted_delta(input_sequence, displacement)


## 通知客户端会话当前本地路线已走完，保留终点直到权威路线完成。
## [param input_sequence] 本次目的地命令的输入序号。
## 返回该序号是否仍属于当前活动预测路线。
func finish_local_predicted_route(input_sequence: int) -> bool:
	if session == null or input_sequence <= 0:
		return false
	return session.finish_local_predicted_route(input_sequence)


## 执行 `show_rejection` 对应的模块操作。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func show_rejection(code: StringName, message: String) -> void:
	_on_command_rejected(code, message)


## 执行 `remote_character` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func remote_character(entity_id: StringName) -> Node2D:
	return remote_characters.get(entity_id) as Node2D


## 查询当前由表现器管理的远端角色数量。
## 返回该函数计算、查询或操作得到的结果。
func remote_character_count() -> int:
	return remote_characters.size()


## 查找鼠标命中的远端玩家；重叠时选择画面上更靠前的角色。
func remote_character_at(world_position: Vector2) -> Dictionary:
	var selected: Node2D
	var selected_entity_id := StringName()
	for entity_id in remote_characters:
		var character := remote_characters[entity_id] as Node2D
		if character == null or not is_instance_valid(character) \
				or not character.has_method("hit_test") \
				or not character.hit_test(world_position):
			continue
		if selected == null or character.global_position.y >= selected.global_position.y:
			selected = character
			selected_entity_id = StringName(entity_id)
	if selected == null:
		return {}
	return {
		"entity_id": String(selected_entity_id),
		"character": selected,
		"display_name": String(selected.get_display_name()) \
			if selected.has_method("get_display_name") else String(selected_entity_id),
	}


## 处理 `_on_local_presentation_state_changed` 对应的信号回调。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：表现器不得写本地角色坐标，否则会与路线控制器形成双写。
func _on_local_presentation_state_changed(state: Dictionary) -> void:
	if not state.has("position"):
		return
	local_character_state_applied.emit(state.duplicate(true))


## 处理 `_on_remote_presentation_state_changed` 对应的信号回调。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：所有玩家复用同一 `PlayerWorldAvatar`，地图决定人形/战车模式，实际装备决定外观。
func _on_remote_presentation_state_changed(entity_id: StringName, state: Dictionary) -> void:
	if entity_id == &"" or not state.has("position"):
		return
	var sex := String(state.get("sex", "male"))
	if sex not in ["male", "female"]:
		return
	var character := remote_character(entity_id)
	if character == null:
		character = _create_remote_character(entity_id, sex)
		if character == null:
			return
	character.apply_character_sex(sex, _character_catalog)
	if not character.apply_public_appearance(state.get("appearance", {}), _item_catalog, _character_catalog):
		return
	var presentation: Dictionary = state.get("player_presentation", {})
	if character.presentation_kind != StringName(presentation.get("kind", &"character")):
		if character.apply_map_presentation(presentation) != OK:
			return
		character.combat_status_bar.hide()
	character.position = Vector2(state["position"])
	var direction := posmod(int(state.get("facing_direction", 6)), 8)
	character.set_action(String(state.get("action_id", &"idle")), direction)


## 处理 `_on_remote_entity_removed` 对应的信号回调。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_remote_entity_removed(entity_id: StringName) -> void:
	_remove_remote_character(entity_id)


## 将拾取成功回包分派为玩家增量和幂等世界事件。
## [param event] 服务端提交地面实体移除后生成的权威事件。
## [param change] 同事务的背包与任务变更。
## 设计：世界表现和面板各消费自己的投影，但共享一次服务端事务结果。
func _on_loot_picked_up(event: Dictionary, change: Dictionary) -> void:
	player_change_received.emit(change)
	combat_event_received.emit(event.duplicate(true))


## 将采集结算同时投影到世界提示与玩家组件变化。
## [param event] 调用方传入的 `event` 参数。
## [param change] 同事务的背包、成长和任务变化。
func _on_mining_collected(event: Dictionary, change: Dictionary) -> void:
	player_change_received.emit(change)
	combat_event_received.emit(event.duplicate(true))


## 处理 `_on_connection_state_changed` 对应的信号回调。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_connection_state_changed(state: ClientNetworkAdapter.ConnectionState) -> void:
	match state:
		ClientNetworkAdapter.ConnectionState.CONNECTING:
			network_notice_requested.emit("正在连接服务器…", 2.0)
		ClientNetworkAdapter.ConnectionState.CONNECTED:
			network_notice_requested.emit("已连接服务器", 1.5)
		ClientNetworkAdapter.ConnectionState.DISCONNECTED:
			network_notice_requested.emit("已与服务器断开", 3.0)


## 处理 `_on_connection_failed` 对应的信号回调。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_connection_failed(message: String) -> void:
	last_connection_error_message = message
	push_warning("Connection failed: %s" % message)
	var notice := PlayerErrorMessages.describe(&"connection.failed", message)
	network_notice_requested.emit(notice, 4.0)
	connection_failed.emit(notice)


## 处理 `_on_command_rejected` 对应的信号回调。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_command_rejected(code: StringName, message: String) -> void:
	command_rejected.emit(code, message)
	push_warning("Command rejected [%s]: %s" % [code, message])
	network_notice_requested.emit(_player_error_message(code, message), 4.0)
	system_message_requested.emit(_player_error_message(code, message))


## 处理 `_on_map_change_failed` 对应的信号回调。
## [param transition_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_map_change_failed(
	transition_id: StringName,
	code: StringName,
	message: String,
) -> void:
	map_change_failed.emit(transition_id, code, message)
	push_warning("Map change failed [%s]: %s" % [code, message])
	network_notice_requested.emit(_player_error_message(code, message), 4.0)
	system_message_requested.emit(_player_error_message(code, message))


## 将稳定服务端错误码转换为中央系统提示使用的玩家文案。
## [param code] 服务端错误码。
## [param message] 原始诊断详情，不直接拼接到界面。
## 返回统一中文提示。
func _player_error_message(code: StringName, message: String) -> String:
	return PlayerErrorMessages.describe(code, message)


## 执行 `create_remote_character` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _create_remote_character(entity_id: StringName, sex: String) -> Node2D:
	if not _character_catalog.has(_remote_appearance_key):
		push_error("Remote character appearance is missing: %s" % _remote_appearance_key)
		return null
	var character := PlayerWorldAvatarScript.new()
	character.name = "Remote_%s" % String(entity_id)
	var configured := character.configure(
		CharacterFactoryScript.build_character_set(_character_catalog, _remote_appearance_key, sex),
		_local_character.get_combat_manifest(),
		String(entity_id),
		Color(0.55, 0.9, 1.0),
		PlayerWorldAvatarScript.HUMAN_NAME_LABEL_POSITION,
	)
	if configured != OK:
		character.free()
		return null
	character.set_animation_speed_scale(_remote_animation_speed_scale)
	_remote_parent.add_child(character)
	remote_characters[entity_id] = character
	remote_character_added.emit(entity_id, character)
	return character


## 执行 `remove_remote_character` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _remove_remote_character(entity_id: StringName) -> void:
	var character := remote_character(entity_id)
	if character == null:
		return
	remote_characters.erase(entity_id)
	character.queue_free()
	remote_character_removed.emit(entity_id)
