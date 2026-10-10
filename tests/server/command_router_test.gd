extends SceneTree

const CommandRouterScript := preload("res://scripts/server/command_router.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")

var checks := 0
var failures: Array[String] = []
var messages: Array[Dictionary] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var success := func(_peer_id: int, _payload: Dictionary) -> Dictionary:
		return {"ok": true, "code": &"ok", "value": {"accepted": true}}
	var failure := func(_peer_id: int, payload: Dictionary) -> Dictionary:
		return {"ok": false, "code": &"test.rejected", "message": String(payload.get("message", "rejected"))}
	var send := func(_peer_id: int, message: Dictionary) -> void:
		messages.append(message.duplicate(true))
	var wire := func(result: Dictionary) -> Dictionary:
		var value := result.duplicate(true)
		value["code"] = String(result.get("code", &"unknown"))
		return value
	var router: CommandRouter = CommandRouterScript.new()
	_check(not router.configure(Callable(), Callable(), Callable(), Callable(), Callable(), Callable(), Callable(), Callable(), Callable()).is_ok,
		"router rejects missing handlers")
	_check(router.configure(
		success, failure, success, success, failure, failure, failure, send, wire,
	).is_ok, "router accepts complete handler set")
	router.dispatch(2, CommandRouter.TRANSPORT_SESSION_REQUEST, {})
	_check(messages.back().type == "session_opened", "session success uses session_opened")
	router.dispatch(2, Protocol.MOVE_INTENT, {"message": "move rejected"})
	_check(messages.back().type == "command_rejected", "move failure uses command_rejected")
	router.dispatch(2, Protocol.USE_ABILITY_INTENT, {})
	_check(messages.back().type == "combat_event", "ability success uses combat_event")
	router.dispatch(2, Protocol.PICKUP_LOOT_INTENT, {})
	_check(messages.back().type == "loot_picked_up", "loot success uses loot_picked_up")
	router.dispatch(2, Protocol.VEHICLE_RECOVERY_INTENT, {"input_sequence": 8})
	_check(messages.back().result.value.input_sequence == 8,
		"vehicle recovery failure preserves input sequence metadata")
	router.dispatch(2, CommandRouter.TRANSPORT_PLAYER_PANEL_COMMAND, {
		"type": "prepare_exit",
		"request_id": "0123456789abcdef0123456789abcdef",
	})
	_check(messages.back().result.value.operation == "prepare_exit",
		"failed prepare-exit preserves its request identity")
	router.dispatch(2, Protocol.MAP_TRANSITION_INTENT, {"input_sequence": 9})
	_check(messages.back().result.value.transition_sequence == 9,
		"map transition failure preserves transition sequence metadata")
	router.dispatch(2, &"unsupported", {})
	_check(messages.back().result.code == "network.unsupported_command",
		"unsupported command returns stable error code")
	_check(messages.size() == 8, "each routed command produces exactly one response")
	for failure_message: String in failures:
		push_error(failure_message)
	print("COMMAND_ROUTER_OK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
