class_name CommandRouter
extends RefCounted

const Result := preload("res://scripts/core/domain_result.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const AuthoritativeExitServiceScript := preload(
	"res://scripts/server/persistence/authoritative_exit_service.gd"
)

const TRANSPORT_SESSION_REQUEST: StringName = &"session_request"
const TRANSPORT_PLAYER_PANEL_COMMAND: StringName = &"player_panel_command"

var _session_request_handler: Callable
var _move_handler: Callable
var _ability_handler: Callable
var _loot_handler: Callable
var _vehicle_recovery_handler: Callable
var _player_panel_handler: Callable
var _social_handler: Callable
var _map_transition_handler: Callable
var _send_reliable: Callable
var _wire_result: Callable


## 配置传输命令与应用服务之间的唯一适配边界。
## [param session_request_handler] 会话打开或重连用例。
## [param move_handler] 移动意图用例。
## [param ability_handler] 能力意图用例。
## [param loot_handler] 掉落拾取用例。
## [param vehicle_recovery_handler] 战车恢复用例。
## [param player_panel_handler] 人物、背包、生产和面板用例。
## [param map_transition_handler] 地图切换用例。
## [param send_reliable] 可靠消息发布端口。
## [param wire_result] 内部结果到网络结果的序列化端口。
func configure(
	session_request_handler: Callable,
	move_handler: Callable,
	ability_handler: Callable,
	loot_handler: Callable,
	vehicle_recovery_handler: Callable,
	player_panel_handler: Callable,
	map_transition_handler: Callable,
	send_reliable: Callable,
	wire_result: Callable,
	social_handler: Callable = Callable(),
) -> DomainResult:
	var handlers := [
		session_request_handler,
		move_handler,
		ability_handler,
		loot_handler,
		vehicle_recovery_handler,
		player_panel_handler,
		map_transition_handler,
		send_reliable,
		wire_result,
	]
	for handler: Callable in handlers:
		if not handler.is_valid():
			return Result.failure(&"command_router.invalid_handler", "all command router handlers are required")
	_session_request_handler = session_request_handler
	_move_handler = move_handler
	_ability_handler = ability_handler
	_loot_handler = loot_handler
	_vehicle_recovery_handler = vehicle_recovery_handler
	_player_panel_handler = player_panel_handler
	_social_handler = social_handler
	_map_transition_handler = map_transition_handler
	_send_reliable = send_reliable
	_wire_result = wire_result
	return Result.ok(self)


## 将任意传输实现送达的命令分派到唯一应用服务，并保持既有网络回包语义。
## [param peer_id] 传输层提供且客户端不可伪造的连接标识。
## [param command_type] 会话、移动、战斗、拾取、恢复、面板或地图切换类型。
## [param payload] 已跨过传输复制边界、仍需应用服务校验的载荷。
func dispatch(peer_id: int, command_type: StringName, payload: Dictionary) -> void:
	match command_type:
		TRANSPORT_SESSION_REQUEST:
			var session_result: Dictionary = _session_request_handler.call(peer_id, payload)
			_send(peer_id, {
				"type": "session_opened" if session_result.ok else "command_rejected",
				"result": session_result,
			})
		Protocol.MOVE_INTENT:
			var move_result: Dictionary = _move_handler.call(peer_id, payload)
			if not move_result.ok:
				_send(peer_id, {"type": "command_rejected", "result": move_result})
		Protocol.USE_ABILITY_INTENT:
			var ability_result: Dictionary = _ability_handler.call(peer_id, payload)
			_send(peer_id, {
				"type": "combat_event" if ability_result.ok else "command_rejected",
				"result": ability_result,
			})
		Protocol.PICKUP_LOOT_INTENT:
			var loot_result: Dictionary = _loot_handler.call(peer_id, payload)
			_send(peer_id, {
				"type": "loot_picked_up" if loot_result.ok else "command_rejected",
				"result": loot_result,
			})
		Protocol.VEHICLE_RECOVERY_INTENT:
			var recovery_result: Dictionary = _vehicle_recovery_handler.call(peer_id, payload)
			if recovery_result.ok:
				_send(peer_id, {
					"type": "vehicle_recovery_scheduled", "result": recovery_result,
				})
				return
			var recovery_wire_result := _wire(recovery_result)
			recovery_wire_result["value"] = {
				"command_type": String(Protocol.VEHICLE_RECOVERY_INTENT),
				"input_sequence": int(payload.get("input_sequence", -1)),
			}
			_send_wire(peer_id, {"type": "command_rejected", "result": recovery_wire_result})
		TRANSPORT_PLAYER_PANEL_COMMAND:
			var panel_result: Dictionary = _player_panel_handler.call(peer_id, payload)
			if not panel_result.ok and payload.get("type") == "prepare_exit" \
					and AuthoritativeExitServiceScript.valid_request_id(payload.get("request_id")):
				panel_result["value"] = {
					"operation": "prepare_exit", "request_id": String(payload.request_id),
				}
			_send(peer_id, {
				"type": "player_panels" if panel_result.ok else "command_rejected",
				"result": panel_result,
			})
		Protocol.SOCIAL_COMMAND:
			var social_result: Dictionary = _failure(
				&"network.unsupported_command", "social command handler is not configured"
			)
			if _social_handler.is_valid():
				social_result = _social_handler.call(peer_id, payload)
			_send(peer_id, {
				"type": "social_result" if social_result.ok else "command_rejected",
				"result": social_result,
			})
		Protocol.MAP_TRANSITION_INTENT:
			var transition_result: Dictionary = _map_transition_handler.call(peer_id, payload)
			if transition_result.ok:
				_send(peer_id, {"type": "map_joined", "result": transition_result})
				return
			var transition_wire_result := _wire(transition_result)
			transition_wire_result["value"] = {
				"command_type": String(Protocol.MAP_TRANSITION_INTENT),
				"transition_sequence": int(payload.get("input_sequence", -1)),
			}
			_send_wire(peer_id, {"type": "command_rejected", "result": transition_wire_result})
		_:
			_send(peer_id, {
				"type": "command_rejected",
				"result": _failure(&"network.unsupported_command", "transport command type is not supported"),
			})


func _send(peer_id: int, message: Dictionary) -> void:
	var result: Dictionary = message.get("result", {})
	var wire_message := message.duplicate(true)
	wire_message["result"] = _wire(result)
	_send_wire(peer_id, wire_message)


func _send_wire(peer_id: int, message: Dictionary) -> void:
	_send_reliable.call(peer_id, message)


func _wire(result: Dictionary) -> Dictionary:
	return _wire_result.call(result)


func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
