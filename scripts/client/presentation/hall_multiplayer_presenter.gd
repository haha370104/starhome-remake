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

const SessionScript := preload("res://scripts/client/network/client_multiplayer_session.gd")
const CharacterFactoryScript := preload("res://scripts/characters/character_factory.gd")
const WorldCharacterScript := preload("res://scripts/characters/world_character.gd")

var session: ClientMultiplayerSession
var remote_characters: Dictionary = {}

var _local_character: Node2D
var _remote_parent: Node2D
var _character_catalog: Dictionary = {}
var _status_label: Label
var _remote_appearance_key := "player"
var _remote_animation_speed_scale := 1.0
var _status_timer: Timer
var _status_message := ""
var _status_restore_text := ""


## 绑定本地角色、远端角色父节点、角色素材目录及临时状态文字载体。
## [param local_character] 接收预测与权威坐标的现有玩家角色节点。
## [param remote_parent] 承载远端玩家且参与场景 Y 排序的父节点。
## [param character_catalog] `CharacterFactory` 消费的业务化角色素材配置。
## [param status_label] 用于短暂显示连接状态和拒绝原因的现有 HUD 标签。
## Design: 表现器只投影会话状态，不拥有路径规划、输入采样或传输协议。
func configure(
	local_character: Node2D,
	remote_parent: Node2D,
	character_catalog: Dictionary,
	status_label: Label = null,
) -> void:
	_local_character = local_character
	_remote_parent = remote_parent
	_character_catalog = character_catalog
	_status_label = status_label


## 按 [param settings] 创建并启动客户端会话。
## Returns 启动成功返回 `OK`，配置无效或连接启动失败时返回对应 Godot 错误码。
## Design: `offline_debug_enabled` 必须由调用方显式提供；缺省值始终选择真实网络边界。
func start(settings: Dictionary) -> Error:
	if session != null:
		return ERR_ALREADY_IN_USE
	if _local_character == null or _remote_parent == null or _character_catalog.is_empty():
		return ERR_UNCONFIGURED
	if not settings.has("offline_debug_enabled"):
		return ERR_INVALID_PARAMETER

	_remote_appearance_key = String(settings.get("remote_appearance", "player"))
	_remote_animation_speed_scale = float(settings.get("remote_animation_speed_scale", 1.0))
	_ensure_status_timer()

	session = SessionScript.new()
	session.name = "ClientMultiplayerSession"
	session.offline_debug_enabled = bool(settings["offline_debug_enabled"])
	session.local_entity_id = StringName(settings.get("local_entity_id", &"player.local"))
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
	add_child(session)
	session.initialize_local_player(Vector2(settings.get("initial_position", _local_character.position)))

	if session.offline_debug_enabled:
		_show_temporary_status("离线调试模式", 1.5)
		return OK
	if not bool(settings.get("connect_automatically", true)):
		_show_temporary_status("联机会话尚未连接", 1.5)
		return OK
	var host := String(settings.get("server_host", "127.0.0.1"))
	var port := int(settings.get("server_port", ClientNetworkAdapter.DEFAULT_PORT))
	var connection_error := session.connect_to_server(host, port)
	if connection_error != OK:
		_show_temporary_status("连接失败：%s" % error_string(connection_error), 4.0)
	return connection_error


## 主动断开会话并移除全部远端角色表现节点。
func stop() -> void:
	if session != null:
		session.disconnect_from_server()
	for entity_id in remote_characters.keys():
		_remove_remote_character(StringName(entity_id))


## 向客户端会话提交前往 [param requested_world_point] 的移动意图。
## Returns 创建成功时返回带输入序号的意图字典，会话未启动或地图未就绪时返回空字典。
## Design: 表现器不自行裁剪目标点；调用方应先完成本地导航约束解析。
func request_move(requested_world_point: Vector2) -> Dictionary:
	if session == null:
		return {}
	return session.request_move(requested_world_point)


## Requests the server-owned exit [param transition_id] with its declared [param destination_entry_number].
## [param transition_id] Business transition identifier selected by scene interaction.
## [param destination_entry_number] Destination entrance number from the current map definition.
## Returns the submitted transition payload, or an empty dictionary while unavailable/already pending.
## Design: This presentation seam forwards identifiers only and never resolves a target map or spawn locally.
func request_map_change(
	transition_id: StringName,
	destination_entry_number: int = 0,
) -> Dictionary:
	if session == null:
		return {}
	return session.request_map_change(transition_id, destination_entry_number)


## 将本地路径模拟产生的 [param displacement] 记入 [param input_sequence] 的预测状态。
## Returns 会话接受该输入序号时返回 `true`。
## Design: 权威校正仍由 `ClientMultiplayerSession` 处理，场景不得直接写校正坐标。
func record_local_predicted_delta(input_sequence: int, displacement: Vector2) -> bool:
	if session == null or input_sequence <= 0 or displacement.is_zero_approx():
		return false
	return session.record_local_predicted_delta(input_sequence, displacement)


## 以临时 HUD 文字展示服务端拒绝 [param code] 与可读 [param message]。
func show_rejection(code: StringName, message: String) -> void:
	_on_command_rejected(code, message)


## 返回 [param entity_id] 对应的远端角色节点。
## Returns 实体存在时返回 `WorldCharacter`，否则返回 `null`。
func remote_character(entity_id: StringName) -> Node2D:
	return remote_characters.get(entity_id) as Node2D


## 查询当前由表现器管理的远端角色数量。
## Returns 当前远端角色数量。
func remote_character_count() -> int:
	return remote_characters.size()


## 发布会话本地预测/校正 [param state]，由 `LocalPlayerController` 独占角色位置写入。
## [param state] `LocalMovementPredictor` 发布的表现状态。
## Design: 表现器不得写本地角色坐标，否则会与路线控制器形成双写。
func _on_local_presentation_state_changed(state: Dictionary) -> void:
	if not state.has("position"):
		return
	local_character_state_applied.emit(state.duplicate(true))


## 创建或更新 [param entity_id] 的远端角色表现。
## [param state] 插值器发布的位置、方向和动作状态。
## Design: 所有玩家均经同一 `CharacterFactory` 与 `WorldCharacter` 组合，避免网络角色形成第二套素材体系。
func _on_remote_presentation_state_changed(entity_id: StringName, state: Dictionary) -> void:
	if entity_id == &"" or not state.has("position"):
		return
	var character := remote_character(entity_id)
	if character == null:
		character = _create_remote_character(entity_id)
		if character == null:
			return
	character.position = Vector2(state["position"])
	var direction := posmod(int(state.get("facing_direction", 6)), 8)
	character.set_action(_world_character_action(StringName(state.get("action_id", &"idle"))), direction)


## 响应会话移除 [param entity_id] 的通知并销毁对应远端角色节点。
func _on_remote_entity_removed(entity_id: StringName) -> void:
	_remove_remote_character(entity_id)


## 将 [param state] 转换为短暂的中文连接状态提示。
func _on_connection_state_changed(state: ClientNetworkAdapter.ConnectionState) -> void:
	match state:
		ClientNetworkAdapter.ConnectionState.CONNECTING:
			_show_temporary_status("正在连接服务器…", 2.0)
		ClientNetworkAdapter.ConnectionState.CONNECTED:
			_show_temporary_status("已连接服务器", 1.5)
		ClientNetworkAdapter.ConnectionState.DISCONNECTED:
			_show_temporary_status("已与服务器断开", 3.0)


## 展示底层连接失败的可读 [param message]。
func _on_connection_failed(message: String) -> void:
	_show_temporary_status("连接失败：%s" % message, 4.0)


## 展示服务器拒绝的 [param code] 与可读 [param message]。
func _on_command_rejected(code: StringName, message: String) -> void:
	var detail := message if not message.is_empty() else String(code)
	_show_temporary_status("请求被拒绝：%s" % detail, 4.0)


## Publishes the correlated failure for [param transition_id] and shows its [param code]/[param message].
## [param transition_id] Exit whose authoritative transfer failed.
## [param code] Stable server or protocol failure code.
## [param message] Human-readable rejection detail.
## Design: Scene switching listens to the stable signal; temporary text is presentation-only feedback.
func _on_map_change_failed(
	transition_id: StringName,
	code: StringName,
	message: String,
) -> void:
	map_change_failed.emit(transition_id, code, message)
	var detail := message if not message.is_empty() else String(code)
	_show_temporary_status("切换地图失败：%s" % detail, 4.0)


## 为 [param entity_id] 创建业务化远端角色并加入共享 Y 排序父节点。
## Returns 角色配置存在时返回新节点，配置缺失时报告错误并返回 `null`。
func _create_remote_character(entity_id: StringName) -> Node2D:
	if not _character_catalog.has(_remote_appearance_key):
		push_error("Remote character appearance is missing: %s" % _remote_appearance_key)
		return null
	var character: Node2D = WorldCharacterScript.new()
	character.name = "Remote_%s" % String(entity_id)
	character.configure(
		CharacterFactoryScript.build_character_set(_character_catalog, _remote_appearance_key),
		String(entity_id),
		Color(0.55, 0.9, 1.0),
		Vector2(-66, -158),
	)
	character.set_animation_speed_scale(_remote_animation_speed_scale)
	_remote_parent.add_child(character)
	remote_characters[entity_id] = character
	remote_character_added.emit(entity_id, character)
	return character


## 从场景和索引中移除 [param entity_id] 对应的远端角色。
func _remove_remote_character(entity_id: StringName) -> void:
	var character := remote_character(entity_id)
	if character == null:
		return
	remote_characters.erase(entity_id)
	character.queue_free()
	remote_character_removed.emit(entity_id)


## 将网络动作 [param action_id] 归一化为 `WorldCharacter` 支持的动作键。
## Returns 移动类动作返回 `move`，其他动作暂时安全降级为 `stand`。
func _world_character_action(action_id: StringName) -> String:
	match action_id:
		&"move", &"moving", &"walk", &"walking", &"run", &"running":
			return "move"
		_:
			return "stand"


## 确保临时状态恢复计时器已创建并连接回调。
func _ensure_status_timer() -> void:
	if _status_timer != null:
		return
	_status_timer = Timer.new()
	_status_timer.name = "StatusMessageTimer"
	_status_timer.one_shot = true
	_status_timer.timeout.connect(_on_status_timeout)
	add_child(_status_timer)


## 在 [param duration_seconds] 秒内显示 [param message]，且不覆盖期间出现的新业务提示。
func _show_temporary_status(message: String, duration_seconds: float) -> void:
	if _status_label == null:
		return
	if _status_label.text != _status_message:
		_status_restore_text = _status_label.text
	_status_message = message
	_status_label.text = message
	_status_timer.start(maxf(0.1, duration_seconds))


## 在临时状态仍占用标签时恢复显示前的业务文字。
func _on_status_timeout() -> void:
	if _status_label != null and _status_label.text == _status_message:
		_status_label.text = _status_restore_text
	_status_message = ""
