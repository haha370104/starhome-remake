extends SceneTree

const ConfigScript := preload("res://scripts/server/server_config.gd")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")
const ControllerScript := preload("res://scripts/server/llm/llm_player_controller.gd")
const ToolCallScript := preload("res://scripts/server/llm/llm_tool_call.gd")
const ResultScript := preload("res://scripts/core/domain_result.gd")

const ACTOR_ID := "llm.live_probe"
const MAP_ID := "glory_nft_bl_d04"
const START_POSITION := Vector2(2412.0, 2400.0)

var _server: AuthoritativeServer
var _turns: Array[Dictionary] = []
var _simulate_only := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--validate-only" in OS.get_cmdline_user_args():
		print("LLM_LIVE_PROBE_READY")
		quit(0)
		return
	_simulate_only = "--simulate-only" in OS.get_cmdline_user_args()
	var config := ConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = true
	config.player_state_store_path = "/tmp/starhome_llm_live_probe/player_states.json"
	_server = ServerScript.new()
	var initialized: Dictionary = _server.initialize(config)
	if not initialized.get("ok", false):
		await _finish({"ok": false, "stage": "initialize", "message": initialized.get("message", "")})
		return
	root.add_child(_server)
	var provider: Variant = Callable(self, "_simulate_hunt_decision") if _simulate_only else null
	if not _simulate_only:
		var provider_result: DomainResult = _server.create_openai_llm_provider()
		if not provider_result.is_ok:
			await _finish({"ok": false, "stage": "provider", "message": provider_result.error_message})
			return
		provider = provider_result.value
	var controller: LlmPlayerController = ControllerScript.new()
	controller.turn_completed.connect(_on_turn_completed)
	var spawned: DomainResult = _server.spawn_llm_player(
		ACTOR_ID,
		controller,
		Callable(self, "_resolve_area"),
		provider,
		"Live Probe",
		MAP_ID,
		START_POSITION,
		0.0,
		30.0,
	)
	if not spawned.is_ok:
		await _finish({"ok": false, "stage": "spawn", "message": spawned.error_message})
		return
	var initial_session: ServerSession = _server.sessions.session_for_entity(ACTOR_ID)
	var initial_instance: AuthoritativeMapInstance = _server.map_registry.instance_by_id(
		initial_session.map_instance_id
	)
	var initial_entity: AuthoritativeEntity = initial_instance.entities.get(ACTOR_ID)
	var position_before := [initial_entity.position.x, initial_entity.position.y]
	var combat_events_before := initial_instance.combat_module.combat_events.size() \
		if initial_instance.combat_module != null else 0
	var started_at := Time.get_ticks_msec()
	for _frame in range(1800):
		await process_frame
		if not _turns.is_empty():
			break
	var first_turn_elapsed := Time.get_ticks_msec() - started_at
	for _frame in range(300):
		await process_frame
	var session: ServerSession = _server.sessions.session_for_entity(ACTOR_ID)
	var instance: AuthoritativeMapInstance = _server.map_registry.instance_by_id(session.map_instance_id) \
		if session != null else null
	var entity: AuthoritativeEntity = instance.entities.get(ACTOR_ID) if instance != null else null
	var final_position := [entity.position.x, entity.position.y] if entity != null else []
	var combat_event_count := instance.combat_module.combat_events.size() \
		if instance != null and instance.combat_module != null else 0
	var actor_attacks := 0
	var actor_hits_received := 0
	if instance != null and instance.combat_module != null:
		for event_index: int in range(combat_events_before, combat_event_count):
			var combat_event: Dictionary = instance.combat_module.combat_events[event_index]
			if String(combat_event.get("attacker_id", "")) == ACTOR_ID:
				actor_attacks += 1
			if String(combat_event.get("target_entity_id", "")) == ACTOR_ID:
				actor_hits_received += 1
	var position_changed := final_position.size() == 2 \
		and Vector2(position_before[0], position_before[1]).distance_to(
			Vector2(final_position[0], final_position[1])
		) > 0.1
	var hunt_selected := false
	for turn: Dictionary in _turns:
		if String(turn.get("chosen_action", {}).get("action_kind", "")) == "hunt_monster":
			hunt_selected = true
	var probe_ok := not _turns.is_empty()
	if _simulate_only:
		probe_ok = hunt_selected and (position_changed or combat_event_count > combat_events_before \
			or _server._llm_hunt_behaviors.has(ACTOR_ID))
	await _finish({
		"ok": probe_ok,
		"simulation_only": _simulate_only,
		"actor_id": ACTOR_ID,
		"map_id": MAP_ID,
		"first_turn_elapsed_msec": first_turn_elapsed,
		"turns": _turns,
		"position_before": position_before,
		"position_after": final_position,
		"position_changed": position_changed,
		"combat_event_delta": combat_event_count - combat_events_before,
		"actor_attack_events": actor_attacks,
		"actor_hit_events_received": actor_hits_received,
		"hunt_behavior_active": _server._llm_hunt_behaviors.has(ACTOR_ID),
		"api_key_logged": false,
	})


func _simulate_hunt_decision(frame: Dictionary) -> Variant:
	var hunt_options: Array = frame.get("hunt_options", [])
	if hunt_options.is_empty():
		return ToolCallScript.new("wait", {})
	return ToolCallScript.new("hunt_monster", {
		"species_id": String(hunt_options[0].get("species_id", "")),
		"combat_mode": "stationary",
	})


func _resolve_area(area_id: String, frame: Dictionary) -> DomainResult:
	if area_id not in ["stay", "current", String(frame.get("map_id", ""))]:
		return ResultScript.failure(&"llm.area_unknown", "live probe resolves only the current area")
	var self_state: Dictionary = frame.get("self", {})
	var position := _position_value(self_state.get("position", START_POSITION))
	return ResultScript.ok({
		"map_instance_id": String(frame.get("map_instance_id", "")),
		"target_position": position,
	})


func _position_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return START_POSITION


func _on_turn_completed(turn: RefCounted) -> void:
	var data: Dictionary = turn.to_dictionary()
	var chosen_action: Dictionary = data.get("chosen_action", {})
	var observation: Dictionary = data.get("initial_observation", {})
	var tool_calls: Array[Dictionary] = []
	for call: Dictionary in data.get("tool_calls", []):
		tool_calls.append({
			"tool_id": call.get("tool_id", ""),
			"arguments": call.get("arguments", {}),
			"ok": call.get("ok", false),
			"error_code": call.get("error_code", ""),
		})
	_turns.append({
		"turn_id": data.get("turn_id", ""),
		"trigger_kind": data.get("trigger_kind", ""),
		"status": data.get("status", ""),
		"failure_code": data.get("failure_code", ""),
		"chosen_action": chosen_action,
		"tool_calls": tool_calls,
		"observation_summary": {
			"map_id": observation.get("map_id", ""),
			"visible_entity_count": observation.get("visible_entities", []).size(),
			"hunt_options": observation.get("hunt_options", []),
		},
	})


func _finish(summary: Dictionary) -> void:
	if _server != null and _server.sessions != null \
			and _server.sessions.session_for_entity(ACTOR_ID) != null:
		var saved := _server.despawn_llm_player(ACTOR_ID)
		if not saved.is_ok:
			summary["cleanup_error"] = saved.error_message
	if _server != null and _server.player_state_repository != null:
		var closed := _server.player_state_repository.close()
		if not closed.is_ok:
			summary["cleanup_error"] = closed.error_message
	if _server != null and is_instance_valid(_server):
		_server.queue_free()
		await process_frame
	print("LLM_LIVE_PROBE " + JSON.stringify(summary))
	_server = null
	call_deferred("quit", 0 if bool(summary.get("ok", false)) else 1)
