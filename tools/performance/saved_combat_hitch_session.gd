extends SceneTree

const MainScene := preload("res://scenes/main_hall.tscn")
const CombatTraceLoggerScript := preload("res://scripts/core/combat_trace_logger.gd")
const ServerConfigScript := preload("res://scripts/server/server_config.gd")
const Telemetry := preload("res://scripts/core/performance_telemetry.gd")

const DEFAULT_INTERACTION_SECONDS := 40.0
const HITCH_THRESHOLD_USEC := 25000
const RECENT_EVENT_LIMIT := 12

var _hall: Node
var _session
var _interaction_seconds := DEFAULT_INTERACTION_SECONDS
var _started := false
var _started_at_usec := 0
var _last_frame_usec := 0
var _last_status_second := -1
var _connected := false
var _recent_events: Array[Dictionary] = []
var _event_counts: Dictionary = {}
var _seen_event_ids: Dictionary = {}


## 创建真实大厅并等待存档恢复后的地图完成提交。
func _initialize() -> void:
	var requested_seconds := float(OS.get_environment("STARHOME_COMBAT_HITCH_SECONDS"))
	if requested_seconds > 0.0:
		_interaction_seconds = requested_seconds
	_hall = MainScene.instantiate()
	_hall.multiplayer_offline_debug_enabled = true
	_hall.multiplayer_connect_automatically = false
	root.add_child(_hall)


## 等待进程内权威会话和存档地图都完成，再开始给用户计时。
func _poll_ready() -> void:
	if _hall == null or _hall.multiplayer_presenter == null:
		return
	var presenter = _hall.multiplayer_presenter
	_session = presenter.session
	if _session == null or _session.network_adapter == null:
		return
	if not _connected:
		var save_path := OS.get_environment("STARHOME_COMBAT_HITCH_SAVE")
		if save_path.is_empty() or not FileAccess.file_exists(save_path):
			printerr("SAVED_COMBAT_HITCH_FAIL: set STARHOME_COMBAT_HITCH_SAVE to a copied save file")
			quit(2)
			return
		var config := ServerConfigScript.new()
		config.player_state_store_path = save_path
		if not _session.network_adapter.configure_in_process_server(config):
			printerr("SAVED_COMBAT_HITCH_FAIL: could not configure in-process server")
			quit(2)
			return
		if _session.connect_to_server("in-process", 0) != OK:
			printerr("SAVED_COMBAT_HITCH_FAIL: could not connect in-process server")
			quit(2)
			return
		_connected = true
		return
	if not _session.network_adapter.session_ready:
		return
	var expected_map := String(_session.current_map_id)
	var active_definition = _hall.active_world_controller.definition \
		if _hall.active_world_controller != null else null
	if active_definition == null or String(active_definition.map_id) != expected_map:
		return
	if not presenter.combat_event_received.is_connected(_on_combat_event):
		presenter.combat_event_received.connect(_on_combat_event)
	if not presenter.combat_snapshot_received.is_connected(_on_combat_snapshot):
		presenter.combat_snapshot_received.connect(_on_combat_snapshot)
	Telemetry.configure(true, OS.get_environment(Telemetry.OUTPUT_ENVIRONMENT), {
		"driver": "tools/performance/saved_combat_hitch_session.gd",
		"actual_map_id": expected_map,
		"sample_seconds": _interaction_seconds,
		"warmup_seconds": 0.0,
		"save_path": OS.get_environment("STARHOME_COMBAT_HITCH_SAVE"),
	})
	_started = true
	_started_at_usec = Time.get_ticks_usec()
	_last_frame_usec = _started_at_usec
	print("SAVED_COMBAT_HITCH_READY map=%s duration=%.1fs" % [expected_map, _interaction_seconds])
	print("SAVED_COMBAT_HITCH_CONTROL: 现在开始正常操作，反复触发战车受击卡顿")


## 在用户操作窗口内采集渲染长帧及其最近战斗事件上下文。
func _process(_delta: float) -> bool:
	if not _started:
		_poll_ready()
		return false
	var now_usec := Time.get_ticks_usec()
	var frame_interval_usec := now_usec - _last_frame_usec
	_last_frame_usec = now_usec
	if frame_interval_usec >= HITCH_THRESHOLD_USEC:
		_record_render_hitch(frame_interval_usec)
	var elapsed_seconds := float(now_usec - _started_at_usec) / 1000000.0
	var elapsed_second := floori(elapsed_seconds)
	if elapsed_second != _last_status_second:
		_last_status_second = elapsed_second
		print("SAVED_COMBAT_HITCH_TIME elapsed=%.1f remaining=%.1f events=%s" % [
			elapsed_seconds, maxf(0.0, _interaction_seconds - elapsed_seconds), _event_counts,
		])
	if elapsed_seconds >= _interaction_seconds:
		print("SAVED_COMBAT_HITCH_FINISHED events=%s" % _event_counts)
		quit(0)
	return false


## 记录战斗事件到诊断日志，并保留短窗口供长帧关联。
## [param event] 服务器确认后下发给客户端的战斗事件。
func _on_combat_event(event: Dictionary) -> void:
	_observe_event(event)


## 记录一条去重后的权威战斗事件，兼容可靠消息和快照短事件窗口。
## [param event] 服务端确认的战斗事件。
func _observe_event(event: Dictionary) -> void:
	var event_id := int(event.get("event_id", 0))
	if event_id > 0:
		if _seen_event_ids.has(event_id):
			return
		_seen_event_ids[event_id] = true
	var event_type := String(event.get("event_type", "unknown"))
	_event_counts[event_type] = int(_event_counts.get(event_type, 0)) + 1
	var context := {
		"elapsed_ms": _elapsed_ms(),
		"event_type": event_type,
		"server_tick": int(event.get("server_tick", -1)),
		"impact_tick": int(event.get("impact_tick", -1)),
		"target_entity_id": String(event.get("target_entity_id", "")),
		"damage": int(event.get("damage", 0)),
		"target_health": int(event.get("target_health", -1)),
	}
	_recent_events.append(context)
	while _recent_events.size() > RECENT_EVENT_LIMIT:
		_recent_events.pop_front()
	CombatTraceLoggerScript.record(&"diagnostic", &"combat_event_observed", context)


## 记录快照到达次数，保持与真实主场景信号链一致。
## [param snapshot] 当前客户端收到的权威战斗快照。
func _on_combat_snapshot(snapshot: Dictionary) -> void:
	var events_value: Variant = snapshot.get("recent_events", [])
	if events_value is Array:
		for event: Variant in events_value:
			if event is Dictionary:
				_observe_event(event)
	CombatTraceLoggerScript.record(&"diagnostic", &"combat_snapshot_observed", {
		"elapsed_ms": _elapsed_ms(),
		"server_tick": int(snapshot.get("server_tick", -1)),
		"monster_count": (snapshot.get("monsters", []) as Array).size(),
	})


## 把长帧、服务端当前 tick 和最近受击事件写入后台战斗日志。
## [param frame_interval_usec] 当前渲染帧间隔，单位为微秒。
func _record_render_hitch(frame_interval_usec: int) -> void:
	var server_context := _server_context()
	var record := {
		"elapsed_ms": _elapsed_ms(),
		"frame_interval_ms": float(frame_interval_usec) / 1000.0,
		"recent_events": _recent_events.duplicate(true),
		"server": server_context,
	}
	CombatTraceLoggerScript.record(&"diagnostic", &"render_hitch", record)
	print("SAVED_COMBAT_HITCH_FRAME interval=%.1fms context=%s" % [
		float(frame_interval_usec) / 1000.0, server_context,
	])


## 读取进程内权威服务器的当前战斗摘要，不改变任何运行时状态。
## 返回当前地图、tick、在途攻击和战车状态的诊断字典。
func _server_context() -> Dictionary:
	var network_adapter = _session.network_adapter if _session != null else null
	if _session == null or network_adapter == null:
		return {}
	var endpoint = network_adapter.get("_transport_endpoint")
	var server = endpoint.get("authoritative_server") if endpoint != null else null
	if server == null or server.map_registry == null:
		return {}
	var map_instance_id := String(_session.current_map_instance_id)
	var instance = server.map_registry.instance_by_id(map_instance_id)
	if instance == null or instance.combat_module == null:
		return {"map_instance_id": map_instance_id}
	var actor_id := String(_session.local_entity_id)
	var actor: Dictionary = instance.combat_module.actors.get(actor_id, {})
	var vehicle = actor.get("vehicle_state")
	return {
		"map_instance_id": instance.instance_id,
		"server_tick": int(instance.combat_module.current_tick),
		"monster_count": instance.combat_module.monsters.size(),
		"pending_monster_attacks": instance.combat_module.pending_monster_attacks.size(),
		"combat_event_count": instance.combat_module.combat_events.size(),
		"vehicle_health": int(vehicle.health) if vehicle != null else -1,
	}


## 返回本次诊断窗口开始后的毫秒数。
func _elapsed_ms() -> int:
	return roundi(float(Time.get_ticks_usec() - _started_at_usec) / 1000.0) if _started_at_usec > 0 else 0
