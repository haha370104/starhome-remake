class_name ClientAudioController
extends Node

const CATALOG_PATH := "res://data/audio/glory_audio_v1.json"
const MAX_EFFECT_PLAYERS := 12

var _catalog: Dictionary = {}
var _music := AudioStreamPlayer.new()
var _movement := AudioStreamPlayer.new()
var _mining := AudioStreamPlayer.new()
var _effects: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _seen_events: Dictionary = {}
var _event_order: Array[int] = []
var _local_entity_id := ""
var _current_track := ""
var _listener: Node2D
var _has_combat_baseline := false
var _equipment_signature: Array[String] = []
var _has_equipment_baseline := false


## 建立与客户端音量总线相连的播放器，并加载运行时声音目录。
## [param listener] 用于世界音效距离衰减的本地角色。
## 返回目录和播放器是否可用；缺少物化音频时不阻止游戏启动。
func configure(listener: Node2D) -> bool:
	_listener = listener
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		push_warning("Glory audio catalog is unavailable; run tools/import_glory_audio.py")
		return false
	_catalog = parsed
	for path: String in _catalog.get("effects", {}).values():
		_stream(path)
	_music.bus = &"Music"
	_music.finished.connect(_music.play)
	add_child(_music)
	for loop_player: AudioStreamPlayer in [_movement, _mining]:
		loop_player.bus = &"Effects"
		loop_player.volume_db = -12.0
		loop_player.finished.connect(loop_player.play)
		add_child(loop_player)
	_movement.stream = _effect_stream("movement")
	_mining.stream = _effect_stream("mining")
	for index in MAX_EFFECT_PLAYERS:
		var player := AudioStreamPlayer.new()
		player.name = "Effect_%d" % index
		player.bus = &"Effects"
		player.volume_db = -6.0
		add_child(player)
		_effects.append(player)
	return true


## 根据原客户端地图代码切换配乐，未登记地图保持安静。
## [param definition] 当前已提交的地图定义。
func set_map(definition: MapDefinition) -> void:
	if definition == null or _catalog.is_empty():
		return
	_seen_events.clear()
	_event_order.clear()
	_has_combat_baseline = false
	_set_loop(_mining, false)
	_set_loop(_movement, false)
	var track := ""
	var bindings: Dictionary = _catalog.get("music_by_legacy_code", {})
	for code: String in definition.legacy_codes:
		track = String(bindings.get(code.to_lower(), ""))
		if not track.is_empty():
			break
	if track.is_empty():
		track = String(_catalog.get("remake_fallback_music_by_category", {}).get(
			definition.category, ""
		))
	if track == _current_track:
		return
	_current_track = track
	_music.stop()
	_music.stream = _stream(String(_catalog.get("music", {}).get(track, "")))
	if _music.stream != null:
		_music.play()


## 在本地玩家实际沿路线移动时播放战车行进循环声。
## [param moving] 当前路线是否正在移动。
func set_moving(moving: bool) -> void:
	_set_loop(_movement, moving)


## 从战斗快照同步本地实体和采矿循环声，并接收可能重发的事件。
## [param snapshot] 服务端权威战斗快照。
func on_combat_snapshot(snapshot: Dictionary) -> void:
	_local_entity_id = String(snapshot.get("local_entity_id", _local_entity_id))
	var local_mining: Dictionary = snapshot.get("local_mining", {})
	_set_loop(_mining, bool(local_mining.get("active", false)))
	if not _has_combat_baseline:
		_has_combat_baseline = true
		for raw_event: Variant in snapshot.get("recent_events", []):
			if raw_event is Dictionary:
				_remember_event(int(raw_event.get("event_id", 0)))
		return
	for raw_event: Variant in snapshot.get("recent_events", []):
		if raw_event is Dictionary:
			on_combat_event(raw_event)


## 播放已确认玩法事件，事件号阻止可靠消息与快照重复发声。
## [param event] 服务端已确认的战斗、采矿或拾取事件。
func on_combat_event(event: Dictionary) -> void:
	var event_id := int(event.get("event_id", 0))
	if event_id > 0:
		if _seen_events.has(event_id):
			return
		_remember_event(event_id)
	var event_type := String(event.get("event_type", ""))
	var death: Variant = event.get("death", {})
	var monster_died := death is Dictionary and String(death.get("event_type", "")) == "monster_died"
	match event_type:
		"mining_started":
			if String(event.get("actor_id", "")) == _local_entity_id:
				_set_loop(_mining, true)
		"mining_collected", "loot_picked_up":
			play_effect("pickup")
		"energy_cannon_projectile_spawned":
			_play_world_effect("cannon", event.get("actor_position", []))
		"rocket_launcher_projectile_spawned":
			_play_world_effect("rocket", event.get("actor_position", []))
		"missile_projectile_spawned":
			_play_world_effect("missile", event.get("actor_position", []))
		"monster_attack_started":
			var cue := "sama_attack" if String(event.get("combat_actor_id", "")) == "glory_npc_128" else "monster_attack"
			_play_world_effect(cue, event.get("origin", []))
		"monster_attack_resolved":
			if int(event.get("damage", 0)) > 0:
				if bool(event.get("target_destroyed", false)):
					_play_world_effect("vehicle_destroyed", event.get("impact_position", []))
				elif String(event.get("target_entity_id", "")) == _local_entity_id:
					play_effect("impact")
		"self_repair_resolved":
			if String(event.get("actor_id", "")) == _local_entity_id:
				play_effect("repair")
		_:
			if event_type.ends_with("_hit") and int(event.get("damage", 0)) > 0 \
					and not monster_died:
				_play_world_effect("impact", event.get("impact_position", []))
	if monster_died:
		_play_world_effect("monster_death", death.get("position", []))


## 只在权威玩家状态中的装备实例发生变化时播放换装音效。
## [param player] 已应用的当前玩家投影。
func on_player_changed(player: Player) -> void:
	var signature: Array[String] = []
	for clothing: Clothing in player.character_equipment.items():
		signature.append("character:%s:%s" % [clothing.character_slot, clothing.instance_id])
	for equipment: VehicleEquipment in player.vehicle.loadout.items():
		signature.append("vehicle:%d:%s" % [equipment.equipment_location, equipment.instance_id])
	signature.sort()
	if _has_equipment_baseline and signature != _equipment_signature:
		play_effect("equipment_unequip" if signature.size() < _equipment_signature.size()
			else "equipment_equip")
	_equipment_signature = signature
	_has_equipment_baseline = true


## 保留最近事件号，防止快照重发造成重复音效。
## [param event_id] 服务端战斗事件序号。
func _remember_event(event_id: int) -> void:
	if event_id <= 0 or _seen_events.has(event_id):
		return
	_seen_events[event_id] = true
	_event_order.append(event_id)
	if _event_order.size() > 128:
		_seen_events.erase(_event_order.pop_front())


## 播放技能升级提示，不改变权威等级和面板状态。
## [param _event] 已确认的升级信息。
func on_skill_level_up(_event: Dictionary) -> void:
	play_effect("level_up")


## 从固定并发播放器池播放一段音效，满池时只允许战车击毁声抢占。
## [param effect_id] 音频目录中的语义音效标识。
## [param attenuation_db] 世界距离产生的额外衰减。
func play_effect(effect_id: String, attenuation_db: float = 0.0) -> void:
	var stream := _effect_stream(effect_id)
	if stream == null:
		return
	for player: AudioStreamPlayer in _effects:
		if not player.playing or (effect_id == "vehicle_destroyed" and player == _effects.back()):
			player.stream = stream
			player.volume_db = -6.0 + attenuation_db
			player.play()
			return


## 将已物化 MP3 缓存在内存，避免战斗结算帧访问磁盘。
## [param path] 受控目录中的 res:// MP3 路径。
## 返回可播放流，文件缺失时为空。
func _stream(path: String) -> AudioStreamMP3:
	if path.is_empty():
		return null
	if _streams.has(path):
		return _streams[path]
	if not FileAccess.file_exists(path):
		_streams[path] = null
		push_warning("Missing Glory audio: " + path)
		return null
	var stream := AudioStreamMP3.load_from_buffer(FileAccess.get_file_as_bytes(path))
	_streams[path] = stream
	return stream


## 查询一段已物化的业务音效。
## [param effect_id] 音频目录中的语义标识。
## 返回音频流，未知标识时为空。
func _effect_stream(effect_id: String) -> AudioStreamMP3:
	return _stream(String(_catalog.get("effects", {}).get(effect_id, "")))


## 只在状态切换时启停移动或采矿循环，避免每帧重播。
## [param player] 专用的循环播放器。[param active] 当前状态。
func _set_loop(player: AudioStreamPlayer, active: bool) -> void:
	if active and player.stream != null and not player.playing:
		player.play()
	elif not active and player.playing:
		player.stop()


## 按玩家与事件间距离衰减世界音效。
## [param effect_id] 音效标识。[param position] 权威事件的二维坐标数组。
func _play_world_effect(effect_id: String, position: Variant) -> void:
	if _listener == null or not position is Array or position.size() != 2:
		play_effect(effect_id)
		return
	var point := Vector2(float(position[0]), float(position[1]))
	var distance := _listener.global_position.distance_to(point)
	if distance < 900.0:
		play_effect(effect_id, -18.0 * distance / 900.0)


## 为当前和后续创建的按钮绑定同一轻量点击声。
func connect_ui_buttons() -> void:
	for node: Node in get_tree().root.find_children("*", "BaseButton", true, false):
		_on_node_added(node)
	get_tree().node_added.connect(_on_node_added)


## 对后来创建的按钮补接点击声，不改动各窗口的业务处理。
## [param node] 新进入场景树的节点。
func _on_node_added(node: Node) -> void:
	if node is BaseButton and node.get_viewport() == get_viewport():
		var button := node as BaseButton
		if not button.pressed.is_connected(_on_ui_button_pressed):
			button.pressed.connect(_on_ui_button_pressed)


## 统一播放按钮点击提示。
func _on_ui_button_pressed() -> void:
	play_effect("ui_click")
