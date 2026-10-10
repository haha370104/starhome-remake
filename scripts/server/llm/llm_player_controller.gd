class_name LlmPlayerController
extends Node

const Result = preload("res://scripts/core/domain_result.gd")
const ObservationPolicyScript = preload("res://scripts/server/llm/observation_policy.gd")
const ProgrammaticActionExecutorScript = preload(
	"res://scripts/server/llm/programmatic_action_executor.gd"
)
const HighLevelPlayerActionScript = preload("res://scripts/server/llm/high_level_player_action.gd")
const SimulatedLlmControllerScript = preload("res://scripts/server/llm/simulated_llm_controller.gd")
const AgentEventScript = preload("res://scripts/server/llm/agent_event.gd")
const AgentTurnScript = preload("res://scripts/server/llm/agent_turn.gd")
const LlmToolCallScript = preload("res://scripts/server/llm/llm_tool_call.gd")
const AgentEventClassifierScript = preload("res://scripts/server/llm/llm_agent_event_classifier.gd")
const ToolRegistryScript = preload("res://scripts/server/llm/llm_tool_registry.gd")
const ToolRouterScript = preload("res://scripts/server/llm/llm_tool_router.gd")
const TurnBudgetScript = preload("res://scripts/server/llm/llm_turn_budget.gd")
const WorldStateTrackerScript = preload("res://scripts/server/llm/llm_world_state_tracker.gd")
const LlmTraceLoggerScript = preload("res://scripts/server/llm/llm_trace_logger.gd")
const PlayerMemoryScript = preload("res://scripts/server/llm/llm_player_memory.gd")
const CHAT_EVENT_KINDS: Array[StringName] = [&"chat_received", &"private_chat", &"area_chat", &"party_chat"]
const IDLE_AFTER_ACTION_KINDS: Array[StringName] = [
	HighLevelPlayerActionScript.WAIT, HighLevelPlayerActionScript.SEND_CHAT,
	HighLevelPlayerActionScript.MANAGE_FRIEND, HighLevelPlayerActionScript.USE_ITEM,
	HighLevelPlayerActionScript.EQUIP_ITEM, HighLevelPlayerActionScript.SPLIT_ITEM,
	HighLevelPlayerActionScript.MERGE_ITEMS,
	HighLevelPlayerActionScript.MANAGE_PRODUCTION, HighLevelPlayerActionScript.MANAGE_MAIL,
	HighLevelPlayerActionScript.PICKUP_LOOT, HighLevelPlayerActionScript.TRADE_WITH_NPC,
]

const LOGIN_GAME_INTRODUCTION := "你正在游玩《星际家园复刻版》。这是一款大型科幻多人在线游戏，你将在星球和太空中驾驶战车与飞船，自由探索世界、完成任务、与怪物或其他玩家战斗，并通过采矿、提炼、制造、装备强化和技能成长不断发展自己的角色。随着能力提升，你还可以离开初始星球，前往更多星球和太空区域探索。"

signal intent_submitted(intent: PlayerIntent, result: DomainResult)
signal action_rejected(code: StringName, message: String)
signal safe_idle_changed(is_safe_idle: bool)
signal event_queued(event: RefCounted)
signal turn_started(turn: RefCounted)
signal turn_completed(turn: RefCounted)
signal turn_interrupted(turn: RefCounted)
signal observation_requested(actor_id: String)

var actor_id := ""
var safe_idle := true
var _waiting := false
var _observation_policy: ObservationPolicy
var _executor: ProgrammaticActionExecutor
var _decision_controller: SimulatedLlmController
var _intent_sink: Callable
var _observation: PlayerObservation
var _event_queue: Array[RefCounted] = []
var _submitted_events: Array[RefCounted] = []
var _event_history: Array[RefCounted] = []
var _active_turn: RefCounted
var _turn_sequence := 0
var _turn_history: Array[RefCounted] = []
var _event_classifier: LlmAgentEventClassifier
var _tool_registry: LlmToolRegistry
var _tool_router: LlmToolRouter
var _turn_budget: LlmTurnBudget
var _world_state_tracker: LlmWorldStateTracker
var _latest_world_state_diff: Dictionary = {}
var _active_turn_context: Dictionary = {}
var _game_introduction_delivered := false
var _memory: LlmPlayerMemory
var _provider_failures := 0
var _retry_at_msec := 0
var _wait_until_msec := 0
var _replied_chat_event_ids: Dictionary = {}


func configure(
	requested_actor_id: String,
	area_resolver: Callable,
	intent_sink: Callable,
	decision_provider: Variant,
	decision_delay_seconds := 0.0,
	decision_timeout_seconds := 180.0,
) -> DomainResult:
	if requested_actor_id.is_empty() or not intent_sink.is_valid():
		return Result.failure(&"llm.controller_invalid", "actor and intent sink are required")
	var memory_closed := close_memory()
	if not memory_closed.is_ok: return memory_closed
	_observation_policy = ObservationPolicyScript.new()
	_event_classifier = AgentEventClassifierScript.new()
	_tool_registry = ToolRegistryScript.new()
	_tool_router = ToolRouterScript.new()
	_turn_budget = TurnBudgetScript.new()
	_world_state_tracker = WorldStateTrackerScript.new()
	_latest_world_state_diff.clear()
	var tool_router_result := _tool_router.configure(_tool_registry)
	if not tool_router_result.is_ok:
		return tool_router_result
	var default_tools_result := _register_default_tools()
	if not default_tools_result.is_ok:
		return default_tools_result
	_executor = ProgrammaticActionExecutorScript.new()
	var executor_result := _executor.configure(requested_actor_id, area_resolver)
	if not executor_result.is_ok:
		return executor_result
	if _decision_controller == null:
		_decision_controller = SimulatedLlmControllerScript.new()
		add_child(_decision_controller)
	var provider_result := _decision_controller.configure(
		decision_provider, decision_delay_seconds, decision_timeout_seconds
	)
	if not provider_result.is_ok:
		return provider_result
	_turn_budget.max_wall_clock_msec = roundi(_decision_controller.decision_timeout_seconds * 1000.0) * _turn_budget.max_provider_calls
	if not _decision_controller.action_ready.is_connected(_on_action_ready):
		_decision_controller.action_ready.connect(_on_action_ready)
	if not _decision_controller.tool_call_ready.is_connected(_on_tool_call_ready):
		_decision_controller.tool_call_ready.connect(_on_tool_call_ready)
	if not _decision_controller.decision_failed.is_connected(_on_decision_failed):
		_decision_controller.decision_failed.connect(_on_decision_failed)
	actor_id = requested_actor_id
	_memory = PlayerMemoryScript.new()
	_memory.configure(actor_id)
	_intent_sink = intent_sink
	_event_queue.clear()
	_submitted_events.clear()
	_event_history.clear()
	_active_turn = null
	_active_turn_context.clear()
	_turn_history.clear()
	_turn_sequence = 0
	_game_introduction_delivered = false
	_provider_failures = 0
	_retry_at_msec = 0
	_wait_until_msec = 0
	_waiting = false
	_replied_chat_event_ids.clear()
	_set_safe_idle(true)
	return Result.ok(self)


func configure_memory(directory: String) -> DomainResult:
	return _memory.configure(actor_id, directory)


func close_memory() -> DomainResult:
	return _memory.close() if _memory != null else Result.ok()


func _process(_delta: float) -> void:
	if _wait_until_msec > 0 and _active_turn == null and Time.get_ticks_msec() >= _wait_until_msec:
		_wait_until_msec = 0
		_waiting = false
		enqueue_event({"event_id": "wait.%d" % Time.get_ticks_usec(), "event_kind": "periodic_review", "payload": {"reason": "wait_finished"}}, false)
		observation_requested.emit(actor_id)
		_process_queued_events()
	if _memory == null: return
	var result := _memory.poll_history()
	if result != null:
		enqueue_event({"event_id": "history.%d" % Time.get_ticks_usec(), "event_kind": "history_search_result",
			"payload": {"ok": result.is_ok, "error_code": String(result.error_code), "message": result.error_message, "result": result.value}})


func _exit_tree() -> void:
	if _decision_controller != null: _decision_controller.cancel_pending()
	var closed := close_memory()
	if not closed.is_ok: push_warning(closed.error_message)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		var closed := close_memory()
		if not closed.is_ok: push_warning(closed.error_message)


func submit_authoritative_snapshot(snapshot: Dictionary) -> DomainResult:
	if _observation_policy == null:
		return Result.failure(&"llm.controller_unconfigured", "controller is not configured")
	var observation_result := _observation_policy.build(snapshot)
	if not observation_result.is_ok:
		return observation_result
	return submit_observation(observation_result.value)


func submit_observation(observation: PlayerObservation) -> DomainResult:
	if _executor == null:
		return Result.failure(&"llm.controller_unconfigured", "controller is not configured")
	var accepted := _executor.accept_observation(observation)
	if not accepted.is_ok:
		return accepted
	var diff_result := _world_state_tracker.update(observation)
	if not diff_result.is_ok:
		return diff_result
	_observation = observation
	_latest_world_state_diff = diff_result.value
	_process_queued_events()
	return accepted


## 将语义事件排队；重大事件可以中断当前尚未完成的 provider 决策。
func enqueue_event(raw_event: Variant, process_immediately := true) -> DomainResult:
	var parsed := AgentEventScript.from_dictionary(raw_event)
	if not parsed.is_ok: return parsed
	var event: RefCounted = parsed.value
	if _event_classifier == null:
		return Result.failure(&"llm.controller_unconfigured", "event classifier is not configured")
	var classification := _event_classifier.classify(event.event_kind, _waiting)
	event.interrupts_current_turn = classification == &"interrupt"
	_record_event(event)
	_trace(&"event_queued", event.to_dictionary())
	if classification == &"ignore":
		return Result.ok(event)
	if event.event_kind not in PlayerMemoryScript.EPHEMERAL_EVENTS:
		_memory.record(String(event.event_kind), _observation.map_id if _observation != null else "", event.payload)
	if event.interrupts_current_turn:
		interrupt(event.event_kind)
	elif event.event_kind == &"death" and _active_turn == null:
		_set_safe_idle(true)
	if not _coalesce_pending_event(event):
		_event_queue.append(event)
	event_queued.emit(event)
	if process_immediately:
		_process_queued_events()
	return Result.ok(event)


## 取消当前 provider 决策并回到安全待机；确定性行为的取消由 intent sink 负责。
func interrupt(reason: StringName = &"external_interrupt") -> DomainResult:
	_waiting = false
	_wait_until_msec = 0
	_restore_submitted_events()
	if _decision_controller != null: _decision_controller.cancel_pending()
	if _active_turn == null:
		_set_safe_idle(true)
		return Result.ok()
	_active_turn.interrupt(reason)
	_trace(&"turn_interrupted", {
		"turn_id": _active_turn.turn_id,
		"reason": String(reason),
	})
	_record_turn(_active_turn)
	turn_interrupted.emit(_active_turn)
	_active_turn = null
	_active_turn_context.clear()
	_set_safe_idle(true)
	return Result.ok()


## 请求一次新的 LLM turn；没有观察或已有活动 turn 时拒绝。
func request_decision(trigger_kind: StringName = &"manual", trigger_payload: Dictionary = {}) -> DomainResult:
	if _observation == null or _decision_controller == null:
		return Result.failure(&"llm.observation_required", "submit an observation before requesting a decision")
	if _active_turn != null:
		return Result.failure(&"llm.turn_active", "an LLM turn is already active")
	if Time.get_ticks_msec() < _retry_at_msec:
		return Result.failure(&"llm.provider_backoff", "LLM provider is cooling down after a failed request")
	if Time.get_ticks_msec() < _wait_until_msec:
		return Result.failure(&"llm.action_pause", "行动完成后正在短暂停顿")
	var budget_result := _turn_budget.begin()
	if not budget_result.is_ok:
		return budget_result
	var provider_budget_result := _turn_budget.consume_provider_call()
	if not provider_budget_result.is_ok:
		return provider_budget_result
	_turn_sequence += 1
	var turn: RefCounted = AgentTurnScript.new(
		"%s.turn.%d" % [actor_id, _turn_sequence],
		trigger_kind,
		trigger_payload,
		_observation.observation_revision,
	)
	turn.initial_observation = _observation.to_dictionary()
	turn.world_state_diff = _latest_world_state_diff.duplicate(true)
	_active_turn = turn
	_waiting = false
	_wait_until_msec = 0
	_set_safe_idle(false)
	turn_started.emit(_active_turn)
	_trace(&"turn_started", {
		"turn_id": turn.turn_id,
		"trigger_kind": String(trigger_kind),
		"trigger_payload": trigger_payload,
		"observation_revision": _observation.observation_revision,
	})
	var decision_context := {
		"turn_id": _active_turn.turn_id,
		"trigger_kind": String(trigger_kind),
		"trigger_payload": trigger_payload.duplicate(true),
		"recent_events": recent_event_context(),
		"damage_review": _event_queue.any(func(event: RefCounted) -> bool: return event.event_kind == &"under_attack"),
		"world_state_diff": _latest_world_state_diff.duplicate(true),
		"tools": tool_descriptors(),
		"budget": _turn_budget.snapshot(),
	}
	_memory.observe(_observation)
	decision_context.merge(_memory.context(_observation, trigger_payload))
	if not _game_introduction_delivered:
		decision_context["login_introduction"] = LOGIN_GAME_INTRODUCTION
	_active_turn_context = decision_context.duplicate(true)
	_submitted_events = _event_queue.duplicate()
	_event_queue.clear()
	var requested := _decision_controller.request_decision(
		_observation, _active_turn_context, _turn_budget.remaining_msec() / 1000.0
	)
	if requested.is_ok:
		_game_introduction_delivered = true
		_trace(&"provider_request_started", {
			"turn_id": turn.turn_id,
			"continuation": false,
		})
	if not requested.is_ok:
		_restore_submitted_events()
		_active_turn.fail(requested.error_code, requested.error_message)
		_record_turn(_active_turn)
		turn_completed.emit(_active_turn)
		_active_turn = null
		_active_turn_context.clear()
		_set_safe_idle(true)
		_process_queued_events()
	return requested


func _restore_submitted_events() -> void:
	_event_queue.assign(_submitted_events + _event_queue)
	_submitted_events.clear()


## 取出下一个事件；没有新观察时事件保留在队列中。
func _process_queued_events() -> void:
	if _active_turn != null or _observation == null or _event_queue.is_empty() or Time.get_ticks_msec() < _retry_at_msec: return
	if Time.get_ticks_msec() < _wait_until_msec and not _event_queue.any(func(event: RefCounted) -> bool:
		return event.interrupts_current_turn or event.event_kind == &"under_attack" or _event_classifier.classify(event.event_kind) == &"inbox"): return
	_wait_until_msec = 0
	for event: RefCounted in _event_queue:
		if event.interrupts_current_turn or _event_classifier.classify(event.event_kind, _waiting) in [&"interrupt", &"queue"]:
			request_decision(event.event_kind, event.payload)
			return
	if safe_idle:
		request_decision(_event_queue[0].event_kind, _event_queue[0].payload)


func wait(until_msec := 0) -> void:
	_wait_until_msec = until_msec
	_waiting = _active_turn == null
	if _waiting:
		_set_safe_idle(true)
		_trace(&"wait_started", {"duration_ms": maxi(0, until_msec - Time.get_ticks_msec())})


func _coalesce_pending_event(event: RefCounted) -> bool:
	if _event_classifier == null or not _event_classifier.should_coalesce(event.event_kind):
		return false
	for pending: RefCounted in _event_queue:
		if pending.event_kind != event.event_kind:
			continue
		var incoming_value: Variant = event.payload.get("events", [])
		if incoming_value is Array:
			var merged_value: Variant = pending.payload.get("events", [])
			var merged_events: Array = merged_value.duplicate(true) if merged_value is Array else []
			merged_events.append_array(incoming_value)
			pending.payload["events"] = merged_events
			pending.payload["coalesced_count"] = int(pending.payload.get("coalesced_count", 1)) + 1
		return true
	return false


func pending_event_count() -> int:
	return _event_queue.size()


func event_history() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: RefCounted in _event_history:
		result.append(event.to_dictionary())
	return result


func world_state_diff() -> Dictionary:
	return _latest_world_state_diff.duplicate(true)


func recent_event_context(limit := 8) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := maxi(0, _event_history.size() - maxi(0, limit))
	for index: int in range(start, _event_history.size()):
		if _event_history[index] not in _event_queue:
			result.append(_event_history[index].to_dictionary())
	for event: RefCounted in _event_queue:
		result.append(event.to_dictionary())
	for event_dict: Dictionary in result:
		if StringName(event_dict.event_kind) in CHAT_EVENT_KINDS and _replied_chat_event_ids.has(String(event_dict.event_id)):
			event_dict["replied"] = true
	return result


func active_turn() -> RefCounted:
	return _active_turn


func is_reviewing_damage() -> bool:
	return _active_turn != null and bool(_active_turn_context.get("damage_review", false))


func turn_history() -> Array[RefCounted]:
	return _turn_history.duplicate()


func register_tool(tool: LlmAgentTool, handler := Callable()) -> DomainResult:
	if _tool_registry == null or tool == null:
		return Result.failure(&"llm.tool_invalid", "configured tool is required")
	if tool.tool_kind == "query" and not handler.is_valid():
		return Result.failure(&"llm.tool_invalid", "query tool handler is required")
	var registered := _tool_registry.register(tool)
	if not registered.is_ok:
		return registered
	return _tool_router.bind(tool.tool_id, handler) if tool.tool_kind == "query" else registered


func tool_descriptors() -> Array[Dictionary]:
	if _tool_registry == null:
		return []
	var descriptors := _tool_registry.descriptors()
	if _active_turn != null and _turn_budget.provider_calls >= _turn_budget.max_provider_calls:
		descriptors = descriptors.filter(func(tool: Dictionary) -> bool: return tool.tool_kind == "action")
	var available_species: Array[String] = []
	var available_merchants: Array[String] = []
	if _observation != null:
		for option: Dictionary in _observation.hunt_options:
			available_species.append(String(option.get("species_id", "")))
		for shop: Dictionary in _observation.npc_shops:
			available_merchants.append(String(shop.get("merchant_id", "")))
	for descriptor: Dictionary in descriptors:
		var tool_id := String(descriptor.get("name", ""))
		if tool_id == "hunt_monster" and not available_species.is_empty():
			descriptor["input_schema"]["properties"]["species_id"]["enum"] = available_species
		elif tool_id in ["inspect_npc_shop", "trade_with_npc"] and not available_merchants.is_empty():
			descriptor["input_schema"]["properties"]["merchant_id"]["enum"] = available_merchants
	return descriptors


func invoke_tool(tool_id: String, arguments: Dictionary = {}) -> DomainResult:
	if _active_turn == null:
		return Result.failure(&"llm.turn_missing", "tools can only run during an active turn")
	if _tool_router == null:
		return Result.failure(&"llm.tool_router_unavailable", "tool router is not configured")
	observation_requested.emit(actor_id)
	var budget_result := _turn_budget.consume_tool_call()
	if not budget_result.is_ok:
		return budget_result
	var result: DomainResult = _tool_router.invoke(actor_id, tool_id, arguments)
	_active_turn.record_tool_call(tool_id, arguments, result)
	return result


func _register_default_tools() -> DomainResult:
	for definition: LlmAgentTool in [
		LlmAgentTool.new("recall_memories", "回想自己真实经历过的事情；query 用地点、角色、怪物名称或关键词，空字符串查看近期相关经历。历史记录不代表当前状态。", _object_schema({"query": {"type": "string", "maxLength": 256}})),
		LlmAgentTool.new("search_history", "按关键词后台检索自己的完整历史经历。返回 searching 时不要反复查询，完成后由 history_search_result 事件返回最多6条记录；可继续行动或 wait。长记录仅给明确标记的摘要预览，历史不是当前状态。", _object_schema({"query": {"type": "string", "maxLength": 256}})),
		LlmAgentTool.new("update_plan", "保存跨轮保留的当前目标、计划和下一步，不执行游戏动作；完成或放弃计划时将三个字段都设为空字符串。不能用它编造经历。", _object_schema({
			"goal": {"type": "string", "maxLength": 1024}, "plan": {"type": "string", "maxLength": 1024}, "next_step": {"type": "string", "maxLength": 1024},
		})),
		LlmAgentTool.new("inspect_self", "Inspect the player state visible to this agent.", {"type": "object"}),
		LlmAgentTool.new("inspect_vehicle", "查看当前战车的完整面板数据和已装备物品。", {"type": "object"}),
		LlmAgentTool.new("inspect_inventory", "查看当前背包的完整面板数据和所有物品。", {"type": "object"}),
		LlmAgentTool.new("inspect_character", "查看人物的完整面板数据、技能和人物装备。", {"type": "object"}),
		LlmAgentTool.new("inspect_area", "Inspect visible entities and the current area.", {"type": "object"}),
		LlmAgentTool.new("inspect_objectives", "Inspect public objectives in the current observation.", {"type": "object"}),
		LlmAgentTool.new("inspect_friends", "查看好友、仇人和待处理的好友邀请。", {"type": "object"}),
		LlmAgentTool.new("inspect_hunt_options", "Inspect available monster species and counts.", {"type": "object"}),
		LlmAgentTool.new("inspect_npc_shop", "查看当前场景指定NPC商店的商品、售价、玩家金币和可出售物品。", _object_schema({
			"merchant_id": {"type": "string"},
		})),
		LlmAgentTool.new("wait", "停下并等待一段时间（秒）；不传参则一直待机到事件唤醒。", _object_schema({
			"duration_seconds": {"anyOf": [{"type": "number"}, {"type": "null"}]},
		}), "action"),
		LlmAgentTool.new("self_repair", "Start vehicle self-repair; the server checks health, equipment, skill and energy.", _object_schema({}), "action"),
		LlmAgentTool.new("return_to_base", "呼叫基地救援，按普通玩家规则等待三秒后返回基地；适用于战车击毁后的恢复。", _object_schema({}), "action"),
		LlmAgentTool.new("travel_to_area", "前往当前可用出口所指向的地图：自动走到出口并完成传送，不需要再次调用。", _object_schema({
			"area_id": {"type": "string"},
		}), "action"),
		LlmAgentTool.new("hunt_monster", "在当前场景狩猎指定种类的一只怪物；结束后反馈结果，由你决定下一步，不自动换怪续猎。combat_mode 选 stationary 接近后原地打，shuttle 两点往返边走边打，hexagon 绕怪物走正六边形边走边打；走位受有效射程和障碍限制，无法执行时返回失败，不自动改成其他模式。", _object_schema({
			"species_id": {"type": "string"},
			"combat_mode": {"type": "string", "enum": HighLevelPlayerActionScript.COMBAT_MODES},
		}), "action"),
		LlmAgentTool.new("pickup_loot", "拾取当前场景地面物品：先检查拾取资格，再自动靠近并拾取。", _object_schema({
			"loot_id": {"type": "string"},
		}), "action"),
		LlmAgentTool.new("gather_mine", "采集当前场景的矿源：自动靠近，再按装备、技能、距离和能耗规则连续采矿。", _object_schema({
			"source_entity_id": {"type": "string"},
		}), "action"),
		LlmAgentTool.new("harvest_fruit", "采摘植物园的果实：靠近果实后可以采摘，每个果实采摘后需要等待一段时间才能再次成熟。", _object_schema({
			"plant_id": {"type": "string"},
		}), "action"),
		LlmAgentTool.new("manage_objective", "Accept, turn in, or abandon an objective.", _object_schema({
			"objective_id": {"type": "string"},
			"provider_id": {"type": "string"},
			"operation": {"type": "string", "enum": ["accept", "turn_in", "abandon"]},
		}), "action"),
		LlmAgentTool.new("send_chat", "发送区域、队伍或私聊消息；私聊可跨地图联系已知的在线玩家，无需在当前观察中。", _object_schema({
			"channel": {"type": "string", "enum": ["area", "party", "private"]},
			"message": {"type": "string"},
			"target_entity_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
		}), "action"),
		LlmAgentTool.new("manage_party", "Invite, respond, leave, kick, or transfer party leadership.", _object_schema({
			"operation": {"type": "string", "enum": ["invite", "apply", "respond", "leave", "kick", "transfer_leader"]},
			"target_entity_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"invite_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"accept": {"anyOf": [{"type": "boolean"}, {"type": "null"}]},
		}), "action"),
		LlmAgentTool.new("manage_friend", "发送、接受或拒绝好友邀请，也可以删除好友。好友邀请与组队邀请不同。", _object_schema({
			"operation": {"type": "string", "enum": ["invite", "respond", "remove"]},
			"target_entity_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"invite_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"accept": {"anyOf": [{"type": "boolean"}, {"type": "null"}]},
		}), "action"),
		LlmAgentTool.new("manage_trade", "Invite or respond to a trade and edit or confirm its offer.", _object_schema({
			"operation": {"type": "string", "enum": ["invite", "respond", "add_item", "remove_item", "set_currency", "ready", "cancel"]},
			"target_entity_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"invite_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"accept": {"anyOf": [{"type": "boolean"}, {"type": "null"}]},
			"trade_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"instance_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"quantity": {"anyOf": [{"type": "integer"}, {"type": "null"}]},
			"currency": {"anyOf": [{"type": "integer"}, {"type": "null"}]},
		}), "action"),
		LlmAgentTool.new("trade_with_npc", "按商店列表中的商品名称购买一件商品，或出售背包中的物品。", _object_schema({
			"merchant_id": {"type": "string"},
			"operation": {"type": "string", "enum": ["buy", "sell"]},
			"display_name": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"instance_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"quantity": {"anyOf": [{"type": "integer"}, {"type": "null"}]},
		}), "action"),
		LlmAgentTool.new("use_item", "使用背包物品：食品一次一份，能量包按战车缺少的储备能量自动使用。", _object_schema({
			"instance_id": {"type": "string"},
		}), "action"),
		LlmAgentTool.new("equip_item", "装备背包中的人物或战车装备。", _object_schema({
			"instance_id": {"type": "string"},
		}), "action"),
		LlmAgentTool.new("split_item", "从一个背包堆叠中拆出指定数量。", _object_schema({
			"instance_id": {"type": "string"},
			"quantity": {"type": "integer"},
		}), "action"),
		LlmAgentTool.new("merge_items", "将 instance_id 堆叠合入 target_instance_id，超出目标堆叠容量的数量留在源堆叠。", _object_schema({
			"instance_id": {"type": "string"},
			"target_instance_id": {"type": "string"},
		}), "action"),
	]:
		var handlers := {
			"recall_memories": Callable(self, "_recall_memories_tool"),
			"search_history": Callable(self, "_search_history_tool"),
			"update_plan": Callable(self, "_update_plan_tool"),
			"inspect_self": Callable(self, "_inspect_observation_tool").bind("self_state", "self"),
			"inspect_vehicle": Callable(self, "_inspect_observation_tool").bind("vehicle_panel", "vehicle"),
			"inspect_inventory": Callable(self, "_inspect_observation_tool").bind("inventory_panel", "inventory"),
			"inspect_character": Callable(self, "_inspect_observation_tool").bind("character_panel", "character"),
			"inspect_area": Callable(self, "_inspect_area_tool"),
			"inspect_objectives": Callable(self, "_inspect_observation_tool").bind("available_objectives", "available_objectives"),
			"inspect_friends": Callable(self, "_inspect_observation_tool").bind("friend_state"),
			"inspect_hunt_options": Callable(self, "_inspect_observation_tool").bind("hunt_options", "hunt_options"),
			"inspect_npc_shop": Callable(self, "_inspect_npc_shop_tool"),
		}
		var handler: Callable = handlers.get(definition.tool_id, Callable())
		var registered := register_tool(definition, handler)
		if not registered.is_ok:
			return registered
	return Result.ok()


func _recall_memories_tool(_requested_actor_id: String, arguments: Dictionary) -> DomainResult:
	if arguments.query.length() > 256:
		return Result.failure(&"llm.memory_query_invalid", "回忆关键词最多 256 字符")
	return Result.ok({"memories": _memory.recall(_observation.map_id, arguments.query)})


func _update_plan_tool(_requested_actor_id: String, arguments: Dictionary) -> DomainResult:
	return _memory.update_plan(arguments)


func _search_history_tool(_requested_actor_id: String, arguments: Dictionary) -> DomainResult:
	return _memory.search_history(arguments.query)


func _object_schema(properties: Dictionary) -> Dictionary:
	return {"type": "object", "properties": properties, "additionalProperties": false}


func _inspect_observation_tool(_requested_actor_id: String, _arguments: Dictionary, field: String, wrapper := "") -> DomainResult:
	if _observation == null:
		return Result.failure(&"llm.observation_required", "an observation is required before using tools")
	var value: Variant = _observation.get(field)
	if field.ends_with("_panel") and value.is_empty():
		return Result.failure(&"llm.panel_unavailable", "the %s panel is unavailable" % wrapper)
	var snapshot: Variant = value.duplicate(true)
	return Result.ok(snapshot if wrapper.is_empty() else {wrapper: snapshot})


func _inspect_area_tool(_requested_actor_id: String, _arguments: Dictionary) -> DomainResult:
	if _observation == null:
		return Result.failure(&"llm.observation_required", "an observation is required before using tools")
	var area := {
		"map_id": _observation.map_id,
		"visible_entities": _observation.visible_entities.duplicate(true),
		"available_transitions": _observation.available_transitions.duplicate(true),
		"npcs": _observation.npcs.duplicate(true),
		"facilities": _observation.facilities.duplicate(true),
	}
	if not _observation.ground_items.is_empty():
		area["ground_items"] = _observation.ground_items.duplicate(true)
	return Result.ok(area)


func _inspect_npc_shop_tool(_requested_actor_id: String, arguments: Dictionary) -> DomainResult:
	if _observation == null:
		return Result.failure(&"llm.observation_required", "an observation is required before using tools")
	var merchant_id := String(arguments.get("merchant_id", ""))
	for shop: Dictionary in _observation.npc_shops:
		if String(shop.get("merchant_id", "")) == merchant_id:
			var visible_shop := shop.duplicate(true)
			for offer: Dictionary in visible_shop.get("offers", []):
				offer.erase("definition_id")
				offer.erase("category")
			for item: Dictionary in visible_shop.get("sellable_items", []):
				item.erase("definition_id")
			return Result.ok(visible_shop)
	return Result.failure(&"commerce.merchant_not_here", "that NPC shop is not in the current area")

func _on_tool_call_ready(tool_call: LlmToolCall) -> void:
	if _active_turn == null or tool_call == null:
		return
	_provider_failures = 0
	_retry_at_msec = 0
	_trace(&"model_tool_call", tool_call.to_dictionary())
	var tool := _tool_registry.tool_for(tool_call.tool_id)
	if tool != null and tool.tool_kind == "action":
		_handle_action_tool_call(tool_call)
		return
	_submitted_events.clear()
	var tool_result := invoke_tool(tool_call.tool_id, tool_call.arguments)
	_continue_after_tool_call(tool_call, tool_result)


func _continue_after_tool_call(tool_call: LlmToolCall, tool_result: DomainResult) -> void:
	_decision_controller.complete_tool_call(tool_call, _tool_result_dictionary(tool_call, tool_result), actor_id)
	if tool_call.tool_id not in ["update_plan", "recall_memories", "search_history"] + PlayerMemoryScript.STATE_QUERIES:
		var experience := _tool_result_dictionary(tool_call, tool_result)
		experience["arguments"] = tool_call.arguments
		_memory.record("tool_result", _observation.map_id, experience)
	_trace(&"tool_result", {
		"turn_id": _active_turn.turn_id if _active_turn != null else "",
		"tool_call": tool_call.to_dictionary(),
		"result": _tool_result_dictionary(tool_call, tool_result),
	})
	var provider_budget_result := _turn_budget.consume_provider_call()
	if not provider_budget_result.is_ok:
		_finish_turn_failure(provider_budget_result.error_code, provider_budget_result.error_message)
		_set_safe_idle(true)
		_process_queued_events()
		return
	var continuation_context := _active_turn_context.duplicate(true)
	continuation_context.erase("login_introduction")
	continuation_context["last_tool_call"] = tool_call.to_dictionary()
	continuation_context["recent_events"] = recent_event_context()
	continuation_context["damage_review"] = bool(continuation_context.get("damage_review", false)) or _event_queue.any(func(event: RefCounted) -> bool: return event.event_kind == &"under_attack")
	continuation_context["tools"] = tool_descriptors()
	continuation_context["budget"] = _turn_budget.snapshot()
	continuation_context.merge(_memory.context(_observation), true)
	var requested := _decision_controller.request_tool_continuation(
		_observation,
		continuation_context,
		_tool_result_dictionary(tool_call, tool_result),
		_turn_budget.remaining_msec() / 1000.0,
	)
	if not requested.is_ok:
		_finish_turn_failure(requested.error_code, requested.error_message)
		_set_safe_idle(true)
		_process_queued_events()
		return
	_active_turn_context = continuation_context
	_submitted_events = _event_queue.duplicate()
	_event_queue.clear()
	_trace(&"provider_request_started", {
		"turn_id": _active_turn.turn_id if _active_turn != null else "",
		"continuation": true,
		"tool_id": tool_call.tool_id,
	})


func _handle_action_tool_call(tool_call: LlmToolCall) -> void:
	_submitted_events.clear()
	var handling_turn: RefCounted = _active_turn
	# 每个新动作先清除上一次的定时等待；wait 工具解析后会重新写入截止时间。
	_wait_until_msec = 0
	observation_requested.emit(actor_id)
	var tool_budget_result := _turn_budget.consume_tool_call()
	if not tool_budget_result.is_ok:
		_finish_turn_failure(tool_budget_result.error_code, tool_budget_result.error_message)
		_set_safe_idle(true)
		_process_queued_events()
		return
	var action_result := _action_for_tool_call(tool_call)
	if not action_result.is_ok:
		_active_turn.record_tool_call(tool_call.tool_id, tool_call.arguments, action_result)
		_continue_after_tool_call(tool_call, action_result)
		return
	var action: HighLevelPlayerAction = action_result.value
	var intent_result := _executor.execute(action)
	if not intent_result.is_ok:
		_active_turn.record_tool_call(tool_call.tool_id, tool_call.arguments, intent_result)
		action_rejected.emit(intent_result.error_code, intent_result.error_message)
		_continue_after_tool_call(tool_call, intent_result)
		return
	var intent: PlayerIntent = intent_result.value
	var routed: Variant = _intent_sink.call(intent)
	var route_result: DomainResult = routed if routed is DomainResult else Result.failure(
		&"llm.intent_rejected", "intent sink returned an invalid result"
	)
	if _active_turn != handling_turn:
		return
	_active_turn.record_tool_call(tool_call.tool_id, tool_call.arguments, route_result)
	_trace(&"intent_result", {
		"turn_id": _active_turn.turn_id,
		"tool_id": tool_call.tool_id,
		"intent": intent.to_dictionary(),
		"ok": route_result.is_ok,
		"error_code": String(route_result.error_code),
		"error_message": route_result.error_message,
		"value": route_result.value,
	})
	if not route_result.is_ok:
		action_rejected.emit(route_result.error_code, route_result.error_message)
		_continue_after_tool_call(tool_call, route_result)
		return
	_decision_controller.complete_tool_call(tool_call, _tool_result_dictionary(tool_call, route_result), actor_id)
	var completed_turn: RefCounted = _active_turn
	completed_turn.complete(action.to_dictionary(), intent.to_dictionary(), route_result)
	_record_turn(completed_turn)
	_active_turn = null
	_active_turn_context.clear()
	turn_completed.emit(completed_turn)
	if action.action_kind == HighLevelPlayerActionScript.SEND_CHAT and route_result.is_ok:
		_mark_recent_chats_as_replied()
	if action.action_kind == HighLevelPlayerActionScript.WAIT or _wait_until_msec > 0: wait(_wait_until_msec)
	_set_safe_idle(_waiting or (action.action_kind in IDLE_AFTER_ACTION_KINDS and not (route_result.value is Dictionary and route_result.value.get("action") == "approaching")))
	intent_submitted.emit(intent, route_result)
	_process_queued_events()


func _action_for_tool_call(tool_call: LlmToolCall) -> DomainResult:
	if _observation == null or _active_turn == null:
		return Result.failure(&"llm.observation_required", "current observation is unavailable")
	var tool := _tool_registry.tool_for(tool_call.tool_id)
	if tool == null or tool.tool_kind != "action":
		return Result.failure(&"llm.tool_unknown", "action tool is not registered")
	var validated := tool.validate_arguments(tool_call.arguments)
	if not validated.is_ok: return validated
	var payload: Dictionary = validated.value
	var operation_fields: Dictionary = HighLevelPlayerActionScript.OPERATION_FIELDS.get(StringName(tool_call.tool_id), {})
	if not operation_fields.is_empty():
		var operation := String(payload.get("operation", ""))
		var operation_payload := {"operation": operation}
		for field: String in operation_fields.get(operation, []):
			if payload.get(field) != null: operation_payload[field] = payload[field]
		payload = operation_payload
	match tool_call.tool_id:
		"wait":
			var duration: Variant = payload.get("duration_seconds")
			if duration != null and (duration is float or duration is int):
				var duration_seconds := float(duration)
				if duration_seconds > 0 and duration_seconds <= 300:
					_wait_until_msec = Time.get_ticks_msec() + roundi(duration_seconds * 1000.0)
			payload.clear()
		"send_chat":
			if String(payload.get("channel", "")) != "private":
				payload.erase("target_entity_id")
			elif payload.get("target_entity_id") == null:
				payload.erase("target_entity_id")
		"trade_with_npc":
			var operation := String(payload.get("operation", ""))
			var npc_trade_payload := {
				"merchant_id": String(payload.get("merchant_id", "")),
				"operation": operation,
			}
			if operation == "buy":
				if payload.get("instance_id") != null or payload.get("quantity") != null:
					return Result.failure(&"llm.tool_arguments_invalid", "purchase cannot include sale fields")
				if payload.get("display_name") != null:
					npc_trade_payload["display_name"] = payload.display_name
			elif operation == "sell":
				if payload.get("display_name") != null:
					return Result.failure(&"llm.tool_arguments_invalid", "sale cannot include a purchase name")
				if payload.get("instance_id") != null:
					npc_trade_payload["instance_id"] = payload.instance_id
				if payload.get("quantity") != null:
					npc_trade_payload["quantity"] = payload.quantity
			payload = npc_trade_payload
	var action_id := "%s.action.%d" % [_active_turn.turn_id, _active_turn.tool_calls.size() + 1]
	var action := HighLevelPlayerActionScript.new(
		action_id,
		StringName(tool_call.tool_id),
		_observation.observation_revision,
		Time.get_ticks_msec() + 10000,
		payload,
	)
	var validation := action.validate()
	return Result.ok(action) if validation.is_ok else validation


func _tool_result_dictionary(tool_call: LlmToolCall, result: DomainResult) -> Dictionary:
	var tool_result := {
		"tool_id": tool_call.tool_id,
		"ok": result.is_ok,
		"value": result.value.duplicate(true) if result.value is Dictionary or result.value is Array else result.value,
		"error_code": String(result.error_code),
		"message": result.error_message,
	}
	if not result.is_ok and tool_call.tool_id == "hunt_monster" and _observation != null:
		tool_result["alternatives"] = _observation.hunt_options.duplicate(true)
	return tool_result


func _on_action_ready(action: HighLevelPlayerAction) -> void:
	_submitted_events.clear()
	_provider_failures = 0
	_retry_at_msec = 0
	_wait_until_msec = 0
	_trace(&"model_action", action.to_dictionary())
	var handling_turn: RefCounted = _active_turn
	var intent_result := _executor.execute(action)
	if not intent_result.is_ok:
		action_rejected.emit(intent_result.error_code, intent_result.error_message)
		_finish_turn_failure(intent_result.error_code, intent_result.error_message, action.to_dictionary())
		_set_safe_idle(true)
		_process_queued_events()
		return
	var intent: PlayerIntent = intent_result.value
	var routed: Variant = _intent_sink.call(intent)
	var route_result: DomainResult = routed if routed is DomainResult else Result.failure(
		&"llm.intent_rejected", "intent sink returned an invalid result"
	)
	if _active_turn != handling_turn or handling_turn == null: return
	handling_turn.complete(action.to_dictionary(), intent.to_dictionary(), route_result)
	_record_turn(handling_turn)
	_active_turn = null
	_active_turn_context.clear()
	turn_completed.emit(handling_turn)
	_trace(&"intent_result", {
		"turn_id": handling_turn.turn_id,
		"intent": intent.to_dictionary(),
		"ok": route_result.is_ok,
		"error_code": String(route_result.error_code),
		"error_message": route_result.error_message,
		"value": route_result.value,
	})
	if route_result.is_ok and (action.action_kind == HighLevelPlayerActionScript.WAIT or _wait_until_msec > 0): wait(_wait_until_msec)
	_set_safe_idle(_waiting or not route_result.is_ok or (action.action_kind in IDLE_AFTER_ACTION_KINDS and not (route_result.value is Dictionary and route_result.value.get("action") == "approaching")))
	intent_submitted.emit(intent, route_result)
	_process_queued_events()


func _on_decision_failed(code: StringName, message: String) -> void:
	_restore_submitted_events()
	_provider_failures = mini(_provider_failures + 1, 4)
	var retry_seconds := 15 * (1 << (_provider_failures - 1))
	_retry_at_msec = Time.get_ticks_msec() + retry_seconds * 1000
	_trace(&"provider_backoff", {"consecutive_failures": _provider_failures, "retry_seconds": retry_seconds})
	_trace(&"decision_failed", {"code": String(code), "message": message})
	action_rejected.emit(code, message)
	_finish_turn_failure(code, message)
	_set_safe_idle(true)
	_process_queued_events()


func _finish_turn_failure(code: StringName, message: String, action := {}) -> void:
	if _active_turn == null: return
	_active_turn.chosen_action = action.duplicate(true) if action is Dictionary else {}
	_active_turn.fail(code, message)
	_record_turn(_active_turn)
	turn_completed.emit(_active_turn)
	_active_turn = null
	_active_turn_context.clear()


func _record_event(event: RefCounted) -> void:
	_event_history.append(event)
	if _event_history.size() > 128: _event_history.pop_front()


func _record_turn(turn: RefCounted) -> void:
	if not turn.chosen_action.is_empty():
		_memory.record("action", _observation.map_id if _observation != null else "", {
			"tool": turn.chosen_action.get("action_kind"), "arguments": turn.chosen_action.get("payload", {}),
			"status": "accepted" if turn.status == &"completed" else String(turn.status),
			"error_code": String(turn.failure_code), "message": turn.failure_message})
	_turn_history.append(turn)
	if _turn_history.size() > 32: _turn_history.pop_front()
	_trace(&"turn_finished", {
		"turn_id": turn.turn_id,
		"duration_ms": turn.finished_at_msec - turn.started_at_msec,
		"provider_calls": _turn_budget.provider_calls,
		"tool_calls_used": _turn_budget.tool_calls,
		"status": String(turn.status),
		"trigger_kind": String(turn.trigger_kind),
		"chosen_action": turn.chosen_action,
		"submitted_intent": turn.submitted_intent,
		"tool_calls": turn.tool_calls,
		"failure_code": String(turn.failure_code),
		"failure_message": turn.failure_message,
		"interruption_reason": String(turn.interruption_reason),
	})


func _set_safe_idle(value: bool) -> void:
	if safe_idle == value:
		return
	safe_idle = value
	_trace(&"safe_idle_changed", {"safe_idle": value})
	safe_idle_changed.emit(safe_idle)


func _mark_recent_chats_as_replied() -> void:
	for event: RefCounted in _event_history + _event_queue:
		if event.event_kind in CHAT_EVENT_KINDS:
			var event_id := String(event.get("event_id"))
			if not event_id.is_empty():
				_replied_chat_event_ids[event_id] = true
	for event_id in _replied_chat_event_ids.keys().slice(0, maxi(0, _replied_chat_event_ids.size() - 32)):
		_replied_chat_event_ids.erase(event_id)


func _trace(stage: StringName, fields: Dictionary = {}) -> void:
	LlmTraceLoggerScript.record(actor_id, stage, fields)
