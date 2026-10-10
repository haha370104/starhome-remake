extends SceneTree

const ConfigScript := preload("res://scripts/server/server_config.gd")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")
const ObservationPolicyScript := preload("res://scripts/server/llm/observation_policy.gd")
const HighLevelPlayerActionScript := preload("res://scripts/server/llm/high_level_player_action.gd")
const PlayerObservationScript := preload("res://scripts/server/llm/player_observation.gd")
const ProgrammaticActionExecutorScript := preload(
	"res://scripts/server/llm/programmatic_action_executor.gd"
)
const LlmPlayerControllerScript := preload("res://scripts/server/llm/llm_player_controller.gd")
const AgentEventScript := preload("res://scripts/server/llm/agent_event.gd")
const LlmToolCallScript := preload("res://scripts/server/llm/llm_tool_call.gd")
const LlmEventBusScript := preload("res://scripts/server/llm/llm_event_bus.gd")
const LlmWakeSchedulerScript := preload("res://scripts/server/llm/llm_wake_scheduler.gd")

class PendingProvider extends LlmProvider:
	var completion: Callable
	var cancellations := 0

	func request_turn(_observation: PlayerObservation, _context: Dictionary, callback: Callable) -> DomainResult:
		completion = callback
		return DomainResult.ok()

	func cancel_turn() -> void:
		cancellations += 1

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_observation_policy()
	_test_action_executor_rejections()
	await _test_event_driven_turns()
	_test_provider_timeout()
	await _test_authoritative_server_route()
	await _test_tool_continuation()
	_test_event_bus_and_wake_scheduler()
	for failure: String in failures:
		push_error(failure)
	print("LLM_PLAYER_VERTICAL_SLICE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_observation_policy() -> void:
	var policy := ObservationPolicyScript.new()
	var result := policy.build({
		"actor_id": "llm.player",
		"observation_revision": 17,
		"map_instance_id": "d04.instance.1",
		"map_id": "glory_nft_bl_d04",
		"self": {
			"entity_id": "llm.player",
			"position": {"x": 100.0, "y": 200.0},
			"action_id": "idle",
			"state_revision": 4,
			"movement_speed": 203.0,
			"inventory": {"secret_item": 99},
		},
		"nearby_entities": [
			{"entity_id": "human.player", "position": {"x": 110.0, "y": 200.0}, "action_id": "idle"},
			{"entity_id": "hidden.player", "position": {"x": 120.0, "y": 200.0}, "hidden": true},
			{"entity_id": "human.only", "position": {"x": 130.0, "y": 200.0}, "visible_to": ["human"]},
			{"entity_id": "monster.1", "entity_kind": "monster", "species_id": "sand_worm", "display_name": "Sand Worm", "alive": true},
			{"entity_id": "monster.2", "entity_kind": "monster", "species_id": "sand_worm", "display_name": "Sand Worm", "alive": true},
			{"entity_id": "monster.3", "entity_kind": "monster", "species_id": "sand_worm", "alive": false},
		],
		"ground_items": [{
			"loot_id": "loot.visible",
			"item_definition_id": "low_grade_gel",
			"display_name": "低级凝胶",
			"quantity": 2,
			"position": [90.0, 210.0],
			"eligible_entity_ids": ["someone.else"],
			"eligible_until_msec": 999999,
			"killer_id": "someone.else",
		}],
		"available_objectives": [
			{"objective_id": "mine", "kind": "collect", "status": "available", "area_id": "ore"},
			{"objective_id": "secret", "kind": "admin", "private": true},
		],
		"recent_events": [{"event_id": "e1", "kind": "spawn", "message": "visible", "server_secret": 7}],
	})
	_check(result.is_ok, "observation policy accepts the authoritative frame")
	var observation: PlayerObservation = result.value
	var public_frame := observation.to_dictionary()
	_check(observation.observation_revision == 17 and not public_frame.has("observation_revision") \
		and not public_frame.has("actor_id") and not public_frame.has("map_instance_id") \
		and not public_frame.self.has("entity_id") and not public_frame.self.has("state_revision"),
		"observation retains internal identity and revision without exposing them to the model")
	_check(public_frame.visible_entities.size() == 1, "observation filters hidden and role-private entities")
	_check(public_frame.hunt_options.size() == 1 \
		and public_frame.hunt_options[0].available_count == 2 \
		and not JSON.stringify(public_frame).contains("monster.1"),
		"observation aggregates living monsters by species without exposing instance IDs")
	_check(observation.ground_items.size() == 1 \
		and observation.ground_items[0].loot_id == "loot.visible" \
		and not observation.ground_items[0].has("eligible_entity_ids") \
		and not observation.ground_items[0].has("killer_id") \
		and not public_frame.has("ground_items"),
		"observation retains public ground items for on-demand area inspection")
	var empty_observation := policy.build({"actor_id": "llm.player", "server_tick": 18})
	_check(empty_observation.is_ok and not empty_observation.value.to_dictionary().has("ground_items"),
		"observation omits ground_items when the scene is empty")
	_check(not public_frame.self.has("inventory"), "observation omits private inventory state")
	_check(not JSON.stringify(public_frame).contains("server_secret"), "observation omits server-only fields")
	_check(public_frame.available_objectives.size() == 1, "observation filters private objectives")
	_check(not policy.build({"actor_id": "llm.player", "server_tick": 1}, &"admin").is_ok,
		"observation policy rejects an unauthorized role")


func _test_action_executor_rejections() -> void:
	var observation := PlayerObservationScript.new(
		"llm.player", 17, "d04.instance.1", "glory_nft_bl_d04", {}, [], [], [], 100,
	)
	var resolver := func(area_id: String, _frame: Dictionary) -> DomainResult:
		return DomainResult.ok({
			"map_instance_id": "d04.instance.1",
			"target_position": Vector2(140.0, 240.0) if area_id == "ore" else Vector2.INF,
		})
	var executor := ProgrammaticActionExecutorScript.new()
	_check(executor.configure("llm.player", resolver).is_ok, "programmatic executor configures")
	_check(executor.accept_observation(observation).is_ok, "executor accepts current observation")
	var expires_at := Time.get_ticks_msec() + 1000
	var action := HighLevelPlayerActionScript.travel_to_area("move.1", 17, expires_at, "ore")
	var intent_result := executor.execute(action)
	_check(intent_result.is_ok, "high-level travel action becomes an ordinary player intent")
	var intent: PlayerIntent = intent_result.value
	_check(intent.intent_kind == &"move", "executor emits a move intent kind")
	_check(intent.payload.has("requested_world_point"), "ordinary move contract contains the resolved target")
	_check(not action.to_dictionary().payload.has("requested_world_point"),
		"LLM action does not submit coordinates directly")
	_check(executor.execute(action).error_code == &"llm.action_duplicate", "duplicate action is rejected")
	var stale := HighLevelPlayerActionScript.travel_to_area("move.stale", 16, expires_at, "ore")
	_check(executor.execute(stale).error_code == &"llm.observation_stale", "action from an older observation is rejected")
	var expired := HighLevelPlayerActionScript.travel_to_area(
		"move.expired", 17, Time.get_ticks_msec() - 1, "ore"
	)
	_check(executor.execute(expired).error_code == &"llm.action_expired", "expired action is rejected")
	var forged := HighLevelPlayerActionScript.new(
		"move.forged", HighLevelPlayerActionScript.TRAVEL_TO_AREA, 17, expires_at,
		{"requested_world_point": Vector2(999999.0, 999999.0)},
	)
	_check(not forged.validate().is_ok, "forged coordinate payload is rejected")
	var unknown_area := HighLevelPlayerActionScript.travel_to_area(
		"move.unknown", 17, expires_at, "unknown"
	)
	_check(not executor.execute(unknown_area).is_ok, "unresolved area is rejected")
	var private_chat := executor.execute(HighLevelPlayerActionScript.send_chat("chat.remote", 17, expires_at, "private", "reply", "remote.player"))
	_check(private_chat.is_ok and private_chat.value.intent_kind == &"chat" \
		and private_chat.value.payload.target_entity_id == "remote.player",
		"private chat accepts a target outside the current observation")


func _test_authoritative_server_route() -> void:
	var config := ConfigScript.new()
	config.network_enabled = false
	config.player_state_store_path = "user://llm_route_test_%d.json" % Time.get_ticks_usec()
	var server: AuthoritativeServer = ServerScript.new()
	_check(server.initialize(config).ok, "LLM route server initializes")
	var opened := server.open_session(791, {
		"protocol_version": config.protocol_version,
		"content_version": config.content_version,
	}, 0)
	_check(opened.ok, "LLM route creates a normal authoritative session")
	var session := server.sessions.session_for_peer(791)
	_check(server.disconnect_session(791, 0).ok, "LLM route takes over only after Human disconnect")
	var actor_id := session.entity_id
	var controller: LlmPlayerController = LlmPlayerControllerScript.new()
	root.add_child(server)
	var provider := func(_frame: Dictionary) -> LlmToolCall:
		return LlmToolCallScript.new("travel_to_area", {"area_id": "stay"})
	var resolver := func(_area_id: String, _frame: Dictionary) -> DomainResult:
		var entity: AuthoritativeEntity = server.map_instance.entities[actor_id]
		return DomainResult.ok({
			"map_instance_id": session.map_instance_id,
			"target_position": entity.position,
		})
	var registered := server.register_llm_player(actor_id, controller, resolver, provider)
	_check(registered.is_ok, "server registers a disconnected actor as LLM-controlled")
	_check(server._llm_wake_scheduler.has_actor(actor_id), "server schedules registered LLM actors")
	var reconnect_blocked := server.open_session(792, {
		"protocol_version": config.protocol_version,
		"content_version": config.content_version,
		"reconnect_token": session.reconnect_token,
	}, 1)
	_check(not reconnect_blocked.ok and reconnect_blocked.code == &"llm.actor_controlled",
		"LLM control blocks Human reclaim before reconnect mutates the session")
	var observed := server.observe_llm_player(actor_id)
	_check(observed.is_ok, "server creates a role-filtered observation")
	var instance := server.map_registry.instance_by_id(session.map_instance_id)
	var ground_item: GameItem = server.player_panel_service.catalog.create(
		"low_grade_gel", {"instance_id": "llm.route.loot.item"}
	).value
	var loot_id := "llm.route.loot"
	instance.combat_module.drop_item(loot_id, instance.instance_id, ground_item, instance.entities[actor_id].position)
	var restricted_loot: Dictionary = instance.combat_module.ground_loot[loot_id]
	restricted_loot["eligible_entity_ids"] = ["llm.route.other"]
	restricted_loot["eligible_until_msec"] = Time.get_ticks_msec() + 120000
	instance.combat_module.ground_loot[loot_id] = restricted_loot
	observed = server.observe_llm_player(actor_id)
	_check(observed.is_ok and controller._observation.ground_items.size() == 1 \
		and String(controller._observation.ground_items[0].get("loot_id", "")) == loot_id,
		"server observation exposes ground loot regardless of pickup eligibility")
	var denied_pickup := server.handle_llm_player_intent(PlayerIntent.new(
		actor_id, &"loot", 1, controller._observation.observation_revision, {"loot_id": loot_id},
	))
	_check(not denied_pickup.is_ok and denied_pickup.error_code == &"loot.not_eligible",
		"LLM pickup uses authoritative party eligibility and returns its rejection: %s %s" % [
			String(denied_pickup.error_code), denied_pickup.error_message,
		])
	_check(server.request_llm_decision(actor_id).is_ok and controller.turn_history().is_empty(),
		"server queues a decision without synchronously executing the provider")
	for _frame in range(8):
		await process_frame
	var queued := server.queue_llm_event(actor_id, {
		"event_id": "server.arrived.1", "event_kind": "destination_reached", "payload": {"area_id": "stay"},
	})
	_check(queued.is_ok, "server queues a semantic LLM event")
	for _frame in range(8):
		await process_frame
	_check(server.map_instance.entities.has(actor_id) and controller.turn_history().any(func(turn: RefCounted) -> bool:
		return turn.status == &"completed" and turn.submitted_intent.get("intent_kind") == "move"
	), "asynchronous tool action reaches the ordinary authoritative movement route")
	_check(server.unregister_llm_player(actor_id).is_ok, "server unregisters LLM control")
	_check(not server._llm_wake_scheduler.has_actor(actor_id), "server removes unregistered LLM actors from the scheduler")
	server.queue_free()
	controller.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))


func _test_provider_timeout() -> void:
	var provider := PendingProvider.new()
	var submitted: Array[PlayerIntent] = []
	var resolver := func(_area_id: String, _frame: Dictionary) -> DomainResult:
		return DomainResult.ok({"map_instance_id": "d04.instance.1", "target_position": Vector2.ZERO})
	var controller: LlmPlayerController = LlmPlayerControllerScript.new()
	root.add_child(controller)
	_check(controller.configure("llm.timeout", resolver, func(intent: PlayerIntent) -> DomainResult:
		submitted.append(intent)
		return DomainResult.ok()
	, provider).is_ok, "timeout controller configures")
	_check(controller.submit_authoritative_snapshot({
		"actor_id": "llm.timeout",
		"observation_revision": 19,
		"map_instance_id": "d04.instance.1",
		"self": {"entity_id": "llm.timeout"},
	}).is_ok, "timeout controller accepts observation")
	_check(controller.request_decision().is_ok, "timeout controller queues provider work")
	controller._decision_controller._process(0.0)
	_check(provider.completion.is_valid() and controller._decision_controller._provider_in_flight,
		"asynchronous provider stays pending after its request queue is empty")
	controller._decision_controller._provider_deadline_msec = Time.get_ticks_msec() - 1
	controller._decision_controller._process(0.0)
	provider.completion.call(DomainResult.ok(LlmToolCallScript.new("wait")))
	_check(controller.safe_idle and controller.active_turn() == null and provider.cancellations == 1 \
		and submitted.is_empty() and controller.turn_history().back().failure_code == "llm.provider_timeout",
		"in-flight timeout cancels the provider and rejects a late successful callback")
	_check(controller.request_decision().error_code == &"llm.provider_backoff", "provider timeout enforces retry backoff")
	controller.queue_free()


func _test_event_driven_turns() -> void:
	var completed: Array[RefCounted] = []
	var provider := func(_frame: Dictionary) -> LlmToolCall:
		return LlmToolCallScript.new("wait")
	var controller: LlmPlayerController = LlmPlayerControllerScript.new()
	root.add_child(controller)
	controller.turn_completed.connect(func(turn: RefCounted) -> void: completed.append(turn))
	_check(controller.configure("llm.events", func(_area_id: String, _frame: Dictionary) -> DomainResult:
		return DomainResult.ok({"map_instance_id": "d04.instance.1", "target_position": Vector2.ZERO})
	, func(_intent: PlayerIntent) -> DomainResult:
		return DomainResult.ok({"accepted": true})
	, provider).is_ok, "event controller configures")
	_check(controller.submit_authoritative_snapshot({
		"actor_id": "llm.events", "observation_revision": 21,
		"map_instance_id": "d04.instance.1", "map_id": "glory_nft_bl_d04",
		"self": {"entity_id": "llm.events"},
	}).is_ok, "event controller accepts observation")
	var queued := controller.enqueue_event(AgentEventScript.new(
		"event.low_health", &"low_health", {"health_ratio": 0.25}, false,
	))
	_check(queued.is_ok and controller.active_turn() != null and completed.is_empty(),
		"event wakes one active turn without executing the provider synchronously")
	_check(not controller.request_decision().is_ok, "active turn rejects duplicate decision")
	for _frame in range(8):
		await process_frame
		if not completed.is_empty(): break
	_check(completed.size() == 1, "event turn completes asynchronously")
	if completed.size() == 1:
		var turn: RefCounted = completed[0]
		_check(turn.status == &"completed" and turn.trigger_kind == &"low_health",
			"completed turn records trigger and outcome")
		_check(turn.trigger_payload.get("health_ratio", 0.0) == 0.25,
			"turn retains event payload for replay")
	controller.queue_free()

	var interrupted: Array[RefCounted] = []
	var delayed: LlmPlayerController = LlmPlayerControllerScript.new()
	root.add_child(delayed)
	delayed.turn_interrupted.connect(func(turn: RefCounted) -> void: interrupted.append(turn))
	_check(delayed.configure("llm.interrupt", func(_area_id: String, _frame: Dictionary) -> DomainResult:
		return DomainResult.ok({"map_instance_id": "d04.instance.1", "target_position": Vector2.ZERO})
	, func(_intent: PlayerIntent) -> DomainResult:
		return DomainResult.ok()
	, provider, 0.2).is_ok, "interrupt controller configures")
	_check(delayed.submit_authoritative_snapshot({
		"actor_id": "llm.interrupt", "observation_revision": 22,
		"map_instance_id": "d04.instance.1", "map_id": "glory_nft_bl_d04",
		"self": {"entity_id": "llm.interrupt"},
	}).is_ok, "interrupt controller accepts observation")
	_check(delayed.request_decision(&"travel_started").is_ok, "interrupt controller starts turn")
	var thinking := delayed.active_turn()
	for kind: StringName in [&"chat_event", &"party_invite", &"death"]:
		delayed.enqueue_event(AgentEventScript.new("event." + String(kind), kind, {}, true))
	_check(delayed.active_turn() == thinking and delayed.pending_event_count() == 3 and interrupted.is_empty(),
		"ordinary social events and death enter the inbox even when marked as interrupting")
	delayed.enqueue_event(AgentEventScript.new("event.transfer", &"forced_transfer"))
	_check(interrupted.size() == 1 and thinking.status == &"interrupted" \
		and thinking.interruption_reason == &"forced_transfer" and delayed.active_turn() != thinking,
		"forced transfer interrupts thinking and starts a replacement turn")
	delayed.queue_free()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _test_tool_continuation() -> void:
	var completed: Array[RefCounted] = []
	var saw_query_result := [false]
	var saw_action_failure := [false]
	var saw_pickup_intent := [false]
	var saw_pickup_failure := [false]
	var saw_login_introduction := [false]
	var login_introduction_absent_after_first_request := [true]
	var provider_calls := [0]
	var provider := func(frame: Dictionary) -> Variant:
		provider_calls[0] += 1
		var turn_context: Dictionary = frame.get("turn", {})
		if provider_calls[0] == 1:
			saw_login_introduction[0] = turn_context.get("login_introduction", "") \
				== LlmPlayerControllerScript.LOGIN_GAME_INTRODUCTION
			return LlmToolCallScript.new("inspect_area")
		if turn_context.has("login_introduction"):
			login_introduction_absent_after_first_request[0] = false
		var tool_result: Dictionary = turn_context.get("tool_result", {})
		if provider_calls[0] == 2:
			var value: Dictionary = tool_result.get("value", {})
			var ground_items: Array = value.get("ground_items", [])
			saw_query_result[0] = bool(turn_context.get("continuation", false)) \
				and bool(tool_result.get("ok", false)) and ground_items.size() == 1 \
				and String(ground_items[0].get("loot_id", "")) == "loot.one"
			return LlmToolCallScript.new("hunt_monster", {"species_id": "unavailable", "combat_mode": "stationary"}, "call_hunt")
		if provider_calls[0] == 3:
			saw_action_failure[0] = bool(turn_context.get("continuation", false)) \
				and not bool(tool_result.get("ok", true)) \
				and String(tool_result.get("error_code", "")) == "llm.target_unavailable" \
				and tool_result.get("alternatives", []).size() == 1
			return LlmToolCallScript.new("pickup_loot", {"loot_id": "loot.one"}, "call_pickup")
		if provider_calls[0] == 4:
			saw_pickup_failure[0] = bool(turn_context.get("continuation", false)) \
				and not bool(tool_result.get("ok", true)) \
				and String(tool_result.get("error_code", "")) == "loot.not_eligible"
		return LlmToolCallScript.new("wait", {}, "call_wait")
	var controller: LlmPlayerController = LlmPlayerControllerScript.new()
	root.add_child(controller)
	controller.turn_completed.connect(func(turn: RefCounted) -> void: completed.append(turn))
	_check(controller.configure("llm.tools", func(_area_id: String, _frame: Dictionary) -> DomainResult:
		return DomainResult.ok({"map_instance_id": "d04.instance.1", "target_position": Vector2.ZERO})
	, func(intent: PlayerIntent) -> DomainResult:
		if intent.intent_kind == &"loot":
			saw_pickup_intent[0] = String(intent.payload.get("loot_id", "")) == "loot.one"
			return DomainResult.failure(&"loot.not_eligible", "actor is not eligible to pick up this party loot")
		return DomainResult.ok()
	, provider).is_ok, "tool controller configures")
	_check(controller.submit_authoritative_snapshot({
		"actor_id": "llm.tools", "observation_revision": 23,
		"map_instance_id": "d04.instance.1", "map_id": "glory_nft_bl_d04",
		"self": {"entity_id": "llm.tools"},
		"nearby_entities": [
			{"entity_id": "monster.one", "entity_kind": "monster", "species_id": "sand_worm", "display_name": "Sand Worm", "alive": true},
		],
		"ground_items": [{
			"loot_id": "loot.one", "item_definition_id": "low_grade_gel",
			"display_name": "低级凝胶", "quantity": 1, "position": [5.0, 5.0],
		}],
	}).is_ok, "tool controller accepts observation")
	_check(controller.request_decision().is_ok, "tool controller starts a turn")
	for _frame in range(8):
		await process_frame
		if not completed.is_empty(): break
	_check(provider_calls[0] == 4 and saw_query_result[0] and saw_action_failure[0] \
		and saw_pickup_intent[0] and saw_pickup_failure[0],
		"area loot query, pickup intent, and rejected pickup continue the same turn")
	_check(saw_login_introduction[0] and login_introduction_absent_after_first_request[0],
		"login introduction is sent only with the first provider request")
	_check(completed.size() == 1 and completed[0].tool_calls.size() == 4 \
		and completed[0].chosen_action.get("action_kind", "") == "wait",
		"tool calls and replanned action share one completed turn")
	_check(controller.request_decision(&"later_turn").is_ok, "controller starts a later turn")
	for _frame in range(4):
		await process_frame
		if completed.size() == 2: break
	_check(provider_calls[0] == 5 and completed.size() == 2 \
		and login_introduction_absent_after_first_request[0],
		"login introduction does not repeat in later turns")
	controller.queue_free()


func _test_event_bus_and_wake_scheduler() -> void:
	var deliveries := [0]
	var event_bus := LlmEventBusScript.new()
	_check(event_bus.configure(func(_actor_id: String, _event: RefCounted) -> DomainResult:
		deliveries[0] += 1
		return DomainResult.ok()
	).is_ok, "event bus configures a delivery callback")
	var event := {
		"event_id": "bus.event.1",
		"event_kind": "objective_changed",
		"payload": {"objective_id": "mine"},
	}
	_check(event_bus.publish("llm.bus", event).is_ok, "event bus publishes a semantic event")
	_check(event_bus.publish("llm.bus", event).is_ok and deliveries[0] == 1,
		"event bus deduplicates one event identity")
	event_bus.clear_actor("llm.bus")
	_check(event_bus.publish("llm.bus", event).is_ok and deliveries[0] == 2,
		"event bus forgets identities when an actor is unregistered")

	var wakes := [0]
	var scheduler := LlmWakeSchedulerScript.new()
	_check(scheduler.configure(func(_actor_id: String) -> DomainResult:
		wakes[0] += 1
		return DomainResult.ok()
	).is_ok and scheduler.register("llm.wake", 1.0).is_ok,
		"wake scheduler registers a periodic actor")
	_check(scheduler.advance(0.5).is_ok and wakes[0] == 0, "wake scheduler waits for its interval")
	_check(scheduler.advance(0.5).is_ok and wakes[0] == 1, "wake scheduler emits one wake at the interval")
	_check(scheduler.advance(5.0).is_ok and wakes[0] == 2, "wake scheduler emits no catch-up burst after a long frame")
	scheduler.unregister("llm.wake")
	_check(scheduler.advance(5.0).is_ok and wakes[0] == 2, "unregistered actors are never woken again")
