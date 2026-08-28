extends SceneTree

const EntitySnapshotContract = preload("res://scripts/network/contracts/entity_snapshot.gd")
const ErrorCodes = preload("res://scripts/network/contracts/network_error_codes.gd")
const MapJoinedContract = preload("res://scripts/network/contracts/map_joined.gd")
const MapTransitionIntentContract = preload("res://scripts/network/contracts/map_transition_intent.gd")
const MessageEnvelopeContract = preload("res://scripts/network/contracts/message_envelope.gd")
const MoveIntentContract = preload("res://scripts/network/contracts/move_intent.gd")
const PositionCorrectionContract = preload("res://scripts/network/contracts/position_correction.gd")
const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const SequenceGateContract = preload("res://scripts/network/contracts/sequence_gate.gd")
const UseAbilityIntentContract = preload("res://scripts/network/contracts/use_ability_intent.gd")

var _passed := 0
var _failed := 0


## 运行全部网络契约用例，并通过进程退出码报告断言汇总结果。
## 设计：测试直接约束线上消息的公开边界，避免客户端与服务器各自漂移。
func _initialize() -> void:
	_test_protocol_configuration()
	_test_error_codes()
	_test_move_intent()
	_test_map_transition_intent()
	_test_use_ability_intent()
	_test_entity_snapshot()
	_test_map_joined()
	_test_position_correction()
	_test_message_envelope()
	_test_sequence_gate()
	if _failed == 0:
		print("Network contract tests passed: %d" % _passed)
		quit(0)
	else:
		push_error("Network contract tests failed: %d passed, %d failed" % [_passed, _failed])
		quit(1)


## 验证协议版本、内容版本及网络频率等公开配置常量。
func _test_protocol_configuration() -> void:
	var file := FileAccess.open("res://data/network/protocol.json", FileAccess.READ)
	_expect_true(file != null, "protocol configuration opens")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_expect_equal(typeof(parsed), TYPE_DICTIONARY, "protocol configuration is a dictionary")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var config: Dictionary = parsed
	_expect_equal(int(config["protocol_version"]), Protocol.PROTOCOL_VERSION, "protocol version matches code")
	_expect_equal(int(config["public_content_version"]), Protocol.PUBLIC_CONTENT_VERSION, "content version matches code")
	_expect_equal(config["message_types"].size(), Protocol.supported_message_types().size(), "message type count matches code")
	_expect_true(Protocol.validate_versions(Protocol.PROTOCOL_VERSION, Protocol.PUBLIC_CONTENT_VERSION).is_ok, "current versions are accepted")
	_expect_error(
		Protocol.validate_versions(Protocol.PROTOCOL_VERSION + 1, Protocol.PUBLIC_CONTENT_VERSION),
		ErrorCodes.UNSUPPORTED_PROTOCOL_VERSION,
		"future protocol version is rejected",
	)
	_expect_error(
		Protocol.validate_versions(Protocol.PROTOCOL_VERSION, Protocol.PUBLIC_CONTENT_VERSION + 1),
		ErrorCodes.CONTENT_VERSION_MISMATCH,
		"content mismatch is rejected",
	)


## 验证网络错误代码集合的稳定性与对外字符串表示。
func _test_error_codes() -> void:
	var codes := ErrorCodes.all()
	var unique := {}
	for code: StringName in codes:
		unique[code] = true
		_expect_true(
			String(code).begins_with("network.") or String(code).begins_with("map_transition."),
			"error code is namespaced: %s" % code,
		)
	_expect_equal(unique.size(), codes.size(), "stable error codes are unique")


## 验证移动意图的构造、序列化、反序列化与非法字段拒绝规则。
## 设计：该用例覆盖客户端输入进入服务器前的完整协议边界。
func _test_move_intent() -> void:
	var intent := MoveIntentContract.new("hall.instance.1", Vector2(480.5, 370.25), 12)
	_expect_true(intent.validate().is_ok, "move intent constructor produces valid contract")
	var restored = MoveIntentContract.from_dictionary(intent.to_dictionary())
	_expect_true(restored.is_ok, "move intent round trip succeeds")
	_expect_equal(restored.value.map_instance_id, intent.map_instance_id, "move intent map instance round trips")
	_expect_equal(restored.value.requested_world_point, intent.requested_world_point, "move intent point round trips")
	_expect_equal(restored.value.input_sequence, 12, "move intent sequence round trips")
	_expect_error(MoveIntentContract.from_dictionary([]), ErrorCodes.INVALID_PAYLOAD, "move intent rejects non-dictionary")
	_expect_error(MoveIntentContract.from_dictionary({}), ErrorCodes.MISSING_FIELD, "move intent rejects missing fields")
	_expect_error(
		MoveIntentContract.from_dictionary({
			"map_instance_id": "bad id",
			"requested_world_point": {"x": 1.0, "y": 2.0},
			"input_sequence": 0,
		}),
		ErrorCodes.INVALID_IDENTIFIER,
		"move intent rejects unsafe identifier",
	)
	_expect_error(
		MoveIntentContract.from_dictionary({
			"map_instance_id": "hall.instance.1",
			"requested_world_point": {"x": Protocol.MAX_WORLD_COORDINATE + 1.0, "y": 2.0},
			"input_sequence": 0,
		}),
		ErrorCodes.VALUE_OUT_OF_RANGE,
		"move intent rejects out-of-world coordinate",
	)
	_expect_error(
		MoveIntentContract.from_dictionary({
			"map_instance_id": "hall.instance.1",
			"requested_world_point": {"x": 1.0, "y": 2.0},
			"input_sequence": 1.5,
		}),
		ErrorCodes.INVALID_FIELD_TYPE,
		"move intent requires integer sequence",
	)
	for forged_field in [&"speed", &"velocity", &"position", &"unknown"]:
		var forged_payload := intent.to_dictionary()
		forged_payload[forged_field] = 99999
		_expect_error(
			MoveIntentContract.from_dictionary(forged_payload),
			ErrorCodes.INVALID_PAYLOAD,
			"move intent rejects forged or unknown field %s" % forged_field,
		)
	var forged_coordinate := intent.to_dictionary()
	forged_coordinate["requested_world_point"]["velocity"] = 1000
	_expect_error(
		MoveIntentContract.from_dictionary(forged_coordinate),
		ErrorCodes.INVALID_PAYLOAD,
		"move intent rejects unknown coordinate fields",
	)


## 验证地图切换意图只携带服务器可校验的出口与入口标识。
## 设计：目标地图和出生坐标属于服务端权威字段，任何客户端夹带都会被拒绝。
func _test_map_transition_intent() -> void:
	var intent := MapTransitionIntentContract.new("field.instance.1", "north_exit", 3, 7)
	_expect_true(intent.validate().is_ok, "map transition intent constructor is valid")
	var restored = MapTransitionIntentContract.from_dictionary(intent.to_dictionary())
	_expect_true(restored.is_ok, "map transition intent round trip succeeds")
	_expect_equal(restored.value.transition_id, "north_exit", "transition ID round trips")
	_expect_equal(restored.value.destination_entry_number, 3, "destination entry round trips")
	_expect_equal(restored.value.input_sequence, 7, "transition sequence round trips")
	for forbidden_field in [&"destination_map_id", &"spawn_position", &"position"]:
		var forged := intent.to_dictionary()
		forged[forbidden_field] = "client_authority"
		_expect_error(
			MapTransitionIntentContract.from_dictionary(forged),
			ErrorCodes.INVALID_PAYLOAD,
			"map transition intent rejects authority field %s" % forbidden_field,
		)
	var negative_entry := intent.to_dictionary()
	negative_entry["destination_entry_number"] = -1
	_expect_error(
		MapTransitionIntentContract.from_dictionary(negative_entry),
		ErrorCodes.VALUE_OUT_OF_RANGE,
		"map transition intent rejects negative entry number",
	)


## 验证技能意图只携带服务器能够独立裁决的技能和目标标识。
## 设计：客户端夹带的伤害、坐标、射程、能耗与冷却必须在契约边界直接拒绝。
func _test_use_ability_intent() -> void:
	var intent := UseAbilityIntentContract.new(
		"d04_field_zone.instance.1", "energy_cannon.primary", "monster.om_adult.1", 9
	)
	_expect_true(intent.validate().is_ok, "use ability constructor is valid")
	var restored = UseAbilityIntentContract.from_dictionary(intent.to_dictionary())
	_expect_true(restored.is_ok, "use ability intent round trip succeeds")
	_expect_equal(restored.value.ability_id, "energy_cannon.primary", "ability ID round trips")
	_expect_equal(restored.value.target_entity_id, "monster.om_adult.1", "target entity round trips")
	_expect_equal(restored.value.input_sequence, 9, "ability sequence round trips")
	for forbidden_field in [
		&"damage",
		&"attack",
		&"target_position",
		&"range",
		&"energy_cost",
		&"cooldown",
	]:
		var forged := intent.to_dictionary()
		forged[forbidden_field] = 999999
		_expect_error(
			UseAbilityIntentContract.from_dictionary(forged),
			ErrorCodes.INVALID_PAYLOAD,
			"use ability intent rejects authority field %s" % forbidden_field,
		)
	var unsafe_target := intent.to_dictionary()
	unsafe_target["target_entity_id"] = "monster with spaces"
	_expect_error(
		UseAbilityIntentContract.from_dictionary(unsafe_target),
		ErrorCodes.INVALID_IDENTIFIER,
		"use ability intent rejects unsafe target identifier",
	)


## 验证实体快照的必填状态、方向动作字段和输入确认序号契约。
func _test_entity_snapshot() -> void:
	var snapshot := EntitySnapshotContract.new(
		"player.2", 400, Vector2(72.0, 96.0), 7, &"walking", 168.0, 9, 44
	)
	_expect_true(snapshot.validate().is_ok, "entity snapshot constructor produces valid contract")
	var restored = EntitySnapshotContract.from_dictionary(snapshot.to_dictionary())
	_expect_true(restored.is_ok, "entity snapshot round trip succeeds")
	_expect_equal(restored.value.entity_id, "player.2", "entity ID round trips")
	_expect_equal(restored.value.facing_direction, 7, "facing direction round trips")
	_expect_equal(restored.value.action_id, &"walking", "action round trips")
	_expect_equal(restored.value.speed, 168.0, "speed round trips")
	_expect_equal(restored.value.acknowledged_input_sequence, 44, "acknowledgement round trips")
	var invalid_facing := snapshot.to_dictionary()
	invalid_facing["facing_direction"] = 8
	_expect_error(EntitySnapshotContract.from_dictionary(invalid_facing), ErrorCodes.VALUE_OUT_OF_RANGE, "snapshot rejects ninth direction")
	var invalid_speed := snapshot.to_dictionary()
	invalid_speed["speed"] = -0.1
	_expect_error(EntitySnapshotContract.from_dictionary(invalid_speed), ErrorCodes.VALUE_OUT_OF_RANGE, "snapshot rejects negative speed")
	var invalid_tick := snapshot.to_dictionary()
	invalid_tick["server_tick"] = "400"
	_expect_error(EntitySnapshotContract.from_dictionary(invalid_tick), ErrorCodes.INVALID_FIELD_TYPE, "snapshot rejects string tick")
	var missing_acknowledgement := snapshot.to_dictionary()
	missing_acknowledgement.erase("acknowledged_input_sequence")
	_expect_error(
		EntitySnapshotContract.from_dictionary(missing_acknowledgement),
		ErrorCodes.MISSING_FIELD,
		"snapshot requires per-entity acknowledgement",
	)
	for deprecated_field in ["direction", "action", "ack_input_sequence"]:
		var legacy_snapshot := snapshot.to_dictionary()
		legacy_snapshot[deprecated_field] = 0
		_expect_error(
			EntitySnapshotContract.from_dictionary(legacy_snapshot),
			ErrorCodes.INVALID_PAYLOAD,
			"snapshot rejects deprecated field %s" % deprecated_field,
		)


## 验证进入地图消息对实例、实体和初始快照的编码约束。
func _test_map_joined() -> void:
	var joined := MapJoinedContract.new(
		"map.yian_harbor.hall_floor_1",
		"hall.instance.1",
		"player.1",
		Vector2(730.0, 1330.0),
		2,
		900,
	)
	_expect_true(joined.validate().is_ok, "map joined constructor produces valid contract")
	var restored = MapJoinedContract.from_dictionary(joined.to_dictionary())
	_expect_true(restored.is_ok, "map joined round trip succeeds")
	_expect_equal(restored.value.map_id, joined.map_id, "map joined map ID round trips")
	_expect_equal(restored.value.map_instance_id, joined.map_instance_id, "map joined instance ID round trips")
	_expect_equal(restored.value.entity_id, joined.entity_id, "map joined entity ID round trips")
	_expect_equal(restored.value.spawn_position, joined.spawn_position, "map joined spawn round trips")
	var zero_version := joined.to_dictionary()
	zero_version["definition_version"] = 0
	_expect_error(MapJoinedContract.from_dictionary(zero_version), ErrorCodes.VALUE_OUT_OF_RANGE, "map joined rejects zero definition version")
	var forged_joined := joined.to_dictionary()
	forged_joined["snapshot"] = {}
	_expect_error(
		MapJoinedContract.from_dictionary(forged_joined),
		ErrorCodes.INVALID_PAYLOAD,
		"map joined keeps snapshot outside its strict contract",
	)


## 验证位置校正消息携带权威坐标、服务器 tick 与确认序号。
func _test_position_correction() -> void:
	var correction := PositionCorrectionContract.new(
		Vector2(849.0, 622.0),
		PositionCorrectionContract.REASON_NAVIGATION,
		44,
		1200,
	)
	_expect_true(correction.validate().is_ok, "position correction constructor produces valid contract")
	var restored = PositionCorrectionContract.from_dictionary(correction.to_dictionary())
	_expect_true(restored.is_ok, "position correction round trip succeeds")
	_expect_equal(restored.value.authoritative_position, correction.authoritative_position, "correction position round trips")
	_expect_equal(restored.value.reason, PositionCorrectionContract.REASON_NAVIGATION, "correction reason round trips")
	_expect_equal(restored.value.acknowledged_input_sequence, 44, "correction acknowledgement round trips")
	var unknown_reason := correction.to_dictionary()
	unknown_reason["reason"] = "client_says_so"
	_expect_error(PositionCorrectionContract.from_dictionary(unknown_reason), ErrorCodes.VALUE_OUT_OF_RANGE, "unknown correction reason is rejected")


## 验证网络消息信封的类型、载荷、时间戳和版本校验规则。
## 设计：信封是所有业务消息共用的传输边界，此处集中锁定兼容性要求。
func _test_message_envelope() -> void:
	var payload := MoveIntentContract.new("hall.instance.1", Vector2(100.0, 200.0), 3).to_dictionary()
	var envelope := MessageEnvelopeContract.new(Protocol.MOVE_INTENT, 5, payload)
	_expect_true(envelope.validate().is_ok, "message envelope constructor produces valid contract")
	var restored = MessageEnvelopeContract.from_dictionary(envelope.to_dictionary())
	_expect_true(restored.is_ok, "message envelope round trip succeeds")
	_expect_equal(restored.value.message_type, Protocol.MOVE_INTENT, "envelope type round trips")
	_expect_equal(restored.value.sequence, 5, "envelope sequence round trips")
	_expect_equal(restored.value.payload, payload, "envelope payload round trips")
	var future_protocol := envelope.to_dictionary()
	future_protocol["protocol_version"] = Protocol.PROTOCOL_VERSION + 1
	_expect_error(MessageEnvelopeContract.from_dictionary(future_protocol), ErrorCodes.UNSUPPORTED_PROTOCOL_VERSION, "envelope rejects unsupported protocol")
	var wrong_content := envelope.to_dictionary()
	wrong_content["content_version"] = Protocol.PUBLIC_CONTENT_VERSION + 1
	_expect_error(MessageEnvelopeContract.from_dictionary(wrong_content), ErrorCodes.CONTENT_VERSION_MISMATCH, "envelope rejects content mismatch")
	var unknown_type := envelope.to_dictionary()
	unknown_type["message_type"] = "unregistered_message"
	_expect_error(MessageEnvelopeContract.from_dictionary(unknown_type), ErrorCodes.UNKNOWN_MESSAGE_TYPE, "envelope rejects unknown message type")
	var invalid_payload := envelope.to_dictionary()
	invalid_payload["payload"] = []
	_expect_error(MessageEnvelopeContract.from_dictionary(invalid_payload), ErrorCodes.INVALID_FIELD_TYPE, "envelope rejects non-dictionary payload")


## 验证序列门对首包、递增包、重复包和乱序包的接受策略。
func _test_sequence_gate() -> void:
	var gate := SequenceGateContract.new()
	_expect_equal(gate.last_accepted(&"movement"), -1, "new stream has no accepted sequence")
	_expect_true(gate.would_accept(&"movement", 0), "first sequence is admissible")
	_expect_true(gate.accept(&"movement", 0).is_ok, "first sequence is accepted")
	_expect_equal(gate.last_accepted(&"movement"), 0, "accepted sequence is recorded")
	_expect_error(gate.accept(&"movement", 0), ErrorCodes.STALE_SEQUENCE, "duplicate sequence is rejected")
	_expect_error(gate.accept(&"movement", -1), ErrorCodes.VALUE_OUT_OF_RANGE, "negative sequence is rejected")
	_expect_error(gate.accept(&"movement", Protocol.MAX_SEQUENCE + 1), ErrorCodes.VALUE_OUT_OF_RANGE, "oversized sequence is rejected")
	_expect_true(gate.accept(&"movement", 2).is_ok, "newer sequence can skip a number")
	_expect_error(gate.accept(&"movement", 1), ErrorCodes.STALE_SEQUENCE, "older sequence is rejected")
	_expect_true(gate.accept(&"interaction", 0).is_ok, "independent stream has independent sequence")
	gate.reset(&"movement")
	_expect_true(gate.accept(&"movement", 0).is_ok, "reset stream accepts initial sequence again")
	gate.reset_all()
	_expect_equal(gate.last_accepted(&"interaction"), -1, "reset all clears every stream")
	_expect_error(gate.accept(&"", 0), ErrorCodes.INVALID_IDENTIFIER, "empty stream ID is rejected")


## 执行 `expect_error` 对应的模块操作。
## [param result] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param expected_code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_error(result: Variant, expected_code: StringName, label: String) -> void:
	_expect_true(not result.is_ok and result.error_code == expected_code, label)


## 执行 `expect_true` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_true(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: %s" % label)


## 执行 `expect_equal` 对应的模块操作。
## [param actual] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param expected] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_expect_true(actual == expected, "%s (expected %s, got %s)" % [label, str(expected), str(actual)])
