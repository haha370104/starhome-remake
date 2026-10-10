extends SceneTree

const ConfigScript := preload("res://scripts/server/llm/llm_provider_config.gd")
const ProviderScript := preload("res://scripts/server/llm/openai_responses_llm_provider.gd")
const PlayerObservationScript := preload("res://scripts/server/llm/player_observation.gd")

var checks := 0
var failures := PackedStringArray()


func _initialize() -> void:
	var config_path := "/tmp/starhome_llm_provider_test_%d.toml" % OS.get_process_id()
	var config_file := FileAccess.open(config_path, FileAccess.WRITE)
	config_file.store_string("model = \"gpt-6.1-sol\"\nmodel_reasoning_effort = \"minimal\"\nbase_url = \"https://proxy.example.invalid\"\nwire_api = \"responses\"\nOPENAI_API_KEY = \"clp_test\"\n")
	config_file.close()
	var file_config_result := ConfigScript.load_file(config_path)
	_check(file_config_result.is_ok, "TOML config file loads with the requested fields")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
	var config_result := ConfigScript.from_dictionary({
		"model": "gpt-6.1-sol",
		"model_reasoning_effort": "minimal",
		"base_url": "https://proxy.example.invalid",
		"wire_api": "responses",
		"OPENAI_API_KEY": "clp_test",
	})
	_check(config_result.is_ok, "combined provider config is valid")
	if not config_result.is_ok:
		_finish()
		return
	var provider = ProviderScript.new()
	_check(provider.configure(config_result.value).is_ok, "OpenAI Responses provider configures")
	var observation := PlayerObservationScript.new(
		"llm.test", 7, "d04.instance.1", "glory_nft_bl_d04", {"health": 100}, [], [], [], 12,
	)
	var context := {
		"turn_id": "llm.test.turn.1",
		"tools": [{
			"name": "hunt_monster",
			"description": "hunt species",
			"input_schema": {
				"type": "object",
				"properties": {"species_id": {"type": "string"}, "combat_mode": {"type": "string", "enum": ["stationary", "shuttle", "hexagon"]}},
			},
			"tool_kind": "action",
		}],
	}
	var payload: Dictionary = provider.build_request_payload(observation, context)
	_check(String(payload.model) == "gpt-6.1-sol", "request uses configured model")
	_check(payload.reasoning.effort == "minimal", "request uses configured reasoning effort")
	_check(provider._endpoint() == "https://proxy.example.invalid/v1/responses", "bare proxy URL gets Responses path")
	_check(payload.tools[0].type == "function" and payload.tools[0].parameters.type == "object", "tools use Responses function format")
	_check(payload.tools[0].strict and payload.tools[0].parameters.required == ["combat_mode", "species_id"] \
		and not payload.tools[0].parameters.additionalProperties, "function schema is strict with all fields required")
	_check(payload.tool_choice == "required" and not payload.parallel_tool_calls,
		"request requires one non-parallel function call")
	var text_result := provider.parse_response({
		"output": [{"type": "message", "content": [{"type": "output_text", "text": "{}"}]}],
	})
	_check(not text_result.is_ok, "free-form action text is rejected")
	var tool_result := provider.parse_response({
		"id": "resp_tool",
		"output": [{"type": "function_call", "call_id": "call_1", "name": "hunt_monster", "arguments": "{\"species_id\":\"sand_worm\",\"combat_mode\":\"hexagon\"}"}],
	})
	_check(tool_result.is_ok and tool_result.value.call_id == "call_1" and tool_result.value.arguments.combat_mode == "hexagon", "Responses function call preserves call id and combat mode")
	_check(not provider.parse_response({
		"output": [{"type": "function_call", "name": "wait", "arguments": "{}"}],
	}).is_ok, "function call without call_id is rejected")
	_check(not provider.parse_response({
		"output": [
			{"type": "function_call", "call_id": "call_1", "name": "wait", "arguments": "{}"},
			{"type": "function_call", "call_id": "call_2", "name": "wait", "arguments": "{}"},
		],
	}).is_ok, "unexpected parallel function calls are rejected")
	var continuation_context := context.duplicate(true)
	continuation_context["last_tool_call"] = tool_result.value.to_dictionary()
	var continuation: Dictionary = provider.build_request_payload(
		observation, continuation_context, {"tool_id": "hunt_monster", "ok": false, "message": "unavailable"}, true,
	)
	_check(continuation.previous_response_id == "resp_tool", "tool continuation uses response id")
	_check(continuation.input[0].type == "function_call_output" and continuation.input[0].call_id == "call_1",
		"tool continuation uses function call output")
	var batch_tool := LlmAgentTool.new("inspect_manufacturing", "制造分层查询", {"type": "object", "properties": {
		"station_id": {"type": "string"}, "recipe_ids": {"type": "array", "items": {"type": "string"}},
	}})
	_check(batch_tool.validate_arguments({"station_id": "refining", "recipe_ids": []}).is_ok \
		and batch_tool.validate_arguments({"station_id": "refining", "recipe_ids": ["iron", "copper"]}).is_ok,
		"batch queries accept both overview and multiple string IDs")
	_check(not batch_tool.validate_arguments({"station_id": "refining", "recipe_ids": "iron"}).is_ok \
		and not batch_tool.validate_arguments({"station_id": "refining", "recipe_ids": ["iron", 1]}).is_ok,
		"batch queries reject non-arrays and non-string IDs")
	var batch_payload: Dictionary = provider.build_request_payload(observation, {"tools": [batch_tool.to_dictionary()]})
	_check(batch_payload.tools[0].parameters.required == ["recipe_ids", "station_id"] \
		and batch_payload.tools[0].parameters.properties.recipe_ids.items.type == "string", "strict Responses schema includes required array and item type")
	_check_input_deduplication(config_result.value)
	_finish()


func _check_input_deduplication(config: LlmProviderConfig) -> void:
	var provider := ProviderScript.new()
	provider.configure(config)
	var observation := PlayerObservationScript.new("llm.test", 1, "map.1", "d04", {"health": 100}, [], [], [], 0)
	observation.hunt_options = [{"species_id": "worm", "available_count": 4}]
	observation.available_transitions = [{"label": "城市", "destination_key": "city"}]
	observation.recent_events = [{"event_id": "combat.1", "kind": "hit", "message": "受击"}]
	var memory := {"kind": "area_seen", "map_id": "d04", "payload": {"name": "城市"}, "knowledge_status": "experienced", "last_observed": 1, "occurrences": 1}
	var context := {"working_memory": {"goal": "探索"}, "last_action": {}, "relevant_memories": [memory],
		"recent_events": [{"event_id": "chat.1", "event_kind": "chat_event", "payload": {"message": "你好"}}]}
	var first := provider._prepare_request(observation, context, {}, false)
	_check(first == provider._prepare_request(observation, context, {}, false) and provider._delivered.is_empty(),
		"building requests never advances the delivery baseline")
	_check(first.input_mode == "full" and _perception(first).observation.hunt_options.size() == 1 \
		and not JSON.stringify(first.input).contains("event_id"), "initial perception includes state without exposing internal event IDs")
	_respond(provider, first)
	context["last_tool_call"] = {"call_id": "call_test"}
	var result := {"tool_id": "inspect_area", "ok": true, "value": {"available_transitions": observation.available_transitions}}
	var repeat := provider._prepare_request(observation, context, result, true)
	_check(_perception(repeat) == {"observation_delta": {}} and repeat.input[0].output == JSON.stringify(result) \
		and repeat.payload.previous_response_id == "resp_test", "unchanged continuation omits perception repeats but keeps complete tool output and response link")
	observation.self_state.health = 93
	observation.hunt_options[0].available_count = 3
	var changed := provider._prepare_request(observation, context, result, true)
	_check(_perception(changed).observation_delta.size() == 2 and _perception(changed).observation_delta.self.health == 93 \
		and _perception(changed).observation_delta.hunt_options[0].available_count == 3,
		"health and monster counts are compared against the last successful model request")
	_respond(provider, changed)
	context.working_memory = {}
	observation.hunt_options.clear()
	observation.available_transitions.clear()
	var cleared := provider._prepare_request(observation, context, result, true)
	_check(_perception(cleared).working_memory == {} and _perception(cleared).observation_delta.hunt_options == [] \
		and _perception(cleared).observation_delta.available_transitions == [], "empty objects and arrays explicitly clear previous values")
	_respond(provider, cleared)
	context.recent_events.append({"event_id": "chat.2", "event_kind": "chat_event", "payload": {"message": "你好"}})
	context.recent_events[0].payload.message = "更新消息"
	observation.recent_events[0].message = "受击更新"
	memory.last_observed = 2
	memory.occurrences = 2
	var events := provider._prepare_request(observation, context, result, true)
	_check(_perception(events).recent_events.size() == 2 and _perception(events).observation_events.size() == 1 \
		and not _perception(events).has("relevant_memories"), "both event sources preserve updates and identical-text new events; memory metadata changes do not repeat content")
	_respond(provider, events)
	memory.payload.name = "植物园"
	memory.knowledge_status = "reported"
	var updated_memory := provider._prepare_request(observation, context, result, true)
	_check(_perception(updated_memory).relevant_memories[0].last_observed == 2 \
		and _perception(updated_memory).relevant_memories[0].knowledge_status == "reported", "changed memory retains its observation time and reliability")
	_respond(provider, updated_memory)
	context.relevant_memories.append({"kind": "action", "payload": {"tool": "wait"}})
	_respond(provider, provider._prepare_request(observation, context, result, true))
	context.relevant_memories.reverse()
	_check(not _perception(provider._prepare_request(observation, context, result, true)).has("relevant_memories"), "memory ordering does not cause retransmission")
	observation.map_instance_id = "map.2"
	_check(provider._prepare_request(observation, context, result, true).input_mode == "full", "map instance changes force a complete observation")
	var failed := provider._prepare_request(observation, context, result, true)
	_respond(provider, failed, [], 500)
	var retry := provider._prepare_request(observation, context, result, true)
	_check(retry.input_mode == "full" and not retry.payload.has("previous_response_id") \
		and _perception(retry).recent_events.size() == 2, "failed requests force resynchronization without swallowing inbox events")
	_respond(provider, retry)
	_respond(provider, provider._prepare_request(observation, context, result, true), [{"type": "compaction"}])
	var compacted := provider._prepare_request(observation, context, result, true)
	_check(compacted.input_mode == "full" and compacted.input[0].call_id == "call_test" \
		and compacted.payload.previous_response_id == "resp_test", "compaction resets perception while preserving the pending tool call chain")
	_respond(provider, compacted)
	var invalid := provider._prepare_request(observation, context, result, true)
	_respond(provider, invalid, [], 200, "incomplete")
	_check(provider._delivered.is_empty() and provider._delivered_items.is_empty(), "incomplete responses cannot confirm delivery")
	_respond(provider, provider._prepare_request(observation, context, {}, false))
	var other := PlayerObservationScript.new("llm.other", 1, "map.2", "d04", {}, [], [], [], 0)
	_check(not provider._prepare_request(other, context, result, true).payload.has("previous_response_id"), "different actors cannot reuse another actor's session")
	_check(provider._prepare_request(observation, context, {}, false).input_mode == "full", "a new unlinked turn must not use stale deltas")
	var bounded := {}
	for index: int in 600:
		provider._unseen_items([{"event_id": str(index), "event_kind": "chat", "payload": {}}], "recent_events", bounded, "llm.test")
	_check(bounded.size() == 512, "deduplication fingerprints have a fixed upper bound")
	provider.cancel_turn()
	_check(provider._delivered.is_empty() and provider._delivered_items.is_empty() \
		and provider._prepare_request(observation, context, {}, false).input_mode == "full", "cancellation clears delivery state")
	_check(first.payload.context_management[0].compact_threshold == 247520, "the agreed 91 percent compaction threshold stays unchanged")


func _perception(prepared: Dictionary) -> Dictionary:
	return JSON.parse_string(prepared.input[-1].content)


func _respond(provider: OpenAIResponsesLlmProvider, prepared: Dictionary, extra: Array = [], status := 200, response_status := "completed") -> void:
	var request := HTTPRequest.new()
	root.add_child(request)
	var actor_id := String(prepared.delivered.actor_id)
	provider._session_actor_id = actor_id
	provider._requests[1] = {"request": request, "completion": func(_result: DomainResult) -> void: pass,
		"actor_id": actor_id, "started_at_msec": Time.get_ticks_msec(), "delivered": prepared.delivered,
		"items": prepared.items, "input_bytes": JSON.stringify(prepared.input).to_utf8_buffer().size(), "input_mode": prepared.input_mode}
	var output := [{"type": "function_call", "call_id": "call_test", "name": "inspect_area", "arguments": "{}"}] + extra
	provider._on_request_completed(HTTPRequest.RESULT_SUCCESS, status, [],
		JSON.stringify({"id": "resp_test", "status": response_status, "output": output}).to_utf8_buffer(), 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	print("OPENAI_RESPONSES_PROVIDER checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
