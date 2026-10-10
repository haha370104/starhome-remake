extends SceneTree

const ConfigScript := preload("res://scripts/server/server_config.gd")
const MapInstanceScript := preload("res://scripts/server/authoritative_map_instance.gd")
const MapTransitionIntentContract := preload("res://scripts/network/contracts/map_transition_intent.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var unconfigured := MapTransitionCoordinator.new()
	_check(not unconfigured.execute(1, {}, 0, 0.0, 64.0, 120.0).ok,
		"未配置协调器拒绝迁移")
	_check(not unconfigured.configure(
		Callable(), Callable(), Callable(), Callable(), Callable(), Callable(), Callable(),
	).is_ok, "缺少迁移端口时拒绝配置")

	var config := ConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = false
	config.dynamic_blocking_enabled = false
	var source: AuthoritativeMapInstance = MapInstanceScript.new()
	var destination: AuthoritativeMapInstance = MapInstanceScript.new()
	_check(source.load_map(config.map_config_path).ok, "迁移源地图加载")
	_check(destination.load_map(config.map_config_path).ok, "迁移目标地图加载")
	destination.definition.map_id = &"fixture_destination"
	destination.definition.legacy_codes = PackedStringArray(["fixture_dest_legacy"])
	destination.instance_id = "fixture_destination.instance.1"
	var transition: MapTransition = source.definition.transitions[0]
	transition.destination_map_id = &"fixture_destination"
	transition.destination_legacy_code = ""
	transition.destination_entry_number = 2
	transition.external_target = false
	transition.enabled = true
	transition.approach_point = config.default_spawn
	transition.has_destination_landing_point = true
	transition.destination_landing_point = config.default_spawn
	var server := AuthoritativeServer.new()
	_check(server.initialize(config, [source, destination]).ok, "服务器组装地图迁移协调器")
	var opened := server.open_session(61, {
		"protocol_version": config.protocol_version,
		"content_version": config.content_version,
	}, 0)
	_check(opened.ok, "建立迁移会话")
	var session: ServerSession = server.sessions.session_for_peer(61)
	var intent := MapTransitionIntentContract.new(
		source.instance_id, String(transition.transition_id), 2, 1,
	).to_dictionary()
	var result := server.handle_peer_map_transition(61, intent)
	_check(result.ok, "协调器提交合法地图迁移")
	_check(not source.entities.has(session.entity_id) and destination.entities.has(session.entity_id),
		"迁移后实体只存在于目标地图")
	_check(session.map_instance_id == destination.instance_id, "迁移后会话切换到目标地图")
	_check(result.value.map_joined.map_instance_id == destination.instance_id,
		"迁移回包来自目标实例")
	var stale := server.handle_peer_map_transition(61, intent)
	_check(not stale.ok, "重复迁移序号被拒绝")
	LlmTraceLogger.enable("/tmp/starhome_map_transition_coordinator_trace.jsonl")
	var controller := LlmPlayerController.new()
	_check(server.spawn_llm_player("llm.transition.test", controller, Callable(server, "resolve_llm_area"),
		func(_frame: Dictionary) -> LlmToolCall: return LlmToolCall.new("wait"),
		"切图测试", String(source.definition.map_id), config.default_spawn).is_ok, "创建使用普通迁移规则的 LLM 玩家")
	var travelled := server.handle_llm_player_intent(PlayerIntent.new("llm.transition.test", &"travel", 1, 0, {
		"map_instance_id": source.instance_id, "transition_id": String(transition.transition_id),
		"destination_map_instance_id": destination.instance_id, "destination_entry_number": 2,
		"requested_world_point": {"x": config.default_spawn.x, "y": config.default_spawn.y},
	}))
	var tool_result := controller._tool_result_dictionary(LlmToolCall.new("travel_to_area", {"area_id": "fixture_destination"}), travelled)
	_check(travelled.is_ok and server.sessions.session_for_entity("llm.transition.test").map_instance_id == destination.instance_id \
		and tool_result.value == {"action": "arrived", "map_id": "fixture_destination", "display_name": destination.definition.display_name},
		"LLM 实际切图和模型工具结果只包含抵达状态与目的地，不含内部快照")
	_check(server.despawn_llm_player("llm.transition.test").is_ok, "LLM 迁移测试正常下线")
	server.free()

	for failure: String in failures:
		push_error(failure)
	print("MAP_TRANSITION_COORDINATOR_OK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
