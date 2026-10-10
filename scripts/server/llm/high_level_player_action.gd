class_name HighLevelPlayerAction
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")
const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")

const WAIT: StringName = &"wait"
const TRAVEL_TO_AREA: StringName = &"travel_to_area"
const HUNT_MONSTER: StringName = &"hunt_monster"
const COMBAT_MODES: Array[String] = ["stationary", "shuttle", "hexagon"]
const GATHER_MINE: StringName = &"gather_mine"
const HARVEST_FRUIT: StringName = &"harvest_fruit"
const SELF_REPAIR: StringName = &"self_repair"
const RETURN_TO_BASE: StringName = &"return_to_base"
const PICKUP_LOOT: StringName = &"pickup_loot"
const MANAGE_OBJECTIVE: StringName = &"manage_objective"
const SEND_CHAT: StringName = &"send_chat"
const MANAGE_PARTY: StringName = &"manage_party"
const MANAGE_FRIEND: StringName = &"manage_friend"
const MANAGE_TRADE: StringName = &"manage_trade"
const TRADE_WITH_NPC: StringName = &"trade_with_npc"
const USE_ITEM: StringName = &"use_item"
const EQUIP_ITEM: StringName = &"equip_item"
const SPLIT_ITEM: StringName = &"split_item"
const MERGE_ITEMS: StringName = &"merge_items"
const MANAGE_PRODUCTION: StringName = &"manage_production"
const MANAGE_MAIL: StringName = &"manage_mail"
const OPERATION_FIELDS := {
	MANAGE_PARTY: {"invite": ["target_entity_id"], "apply": ["target_entity_id"], "respond": ["invite_id", "accept"],
		"leave": [], "kick": ["target_entity_id"], "transfer_leader": ["target_entity_id"]},
	MANAGE_FRIEND: {"invite": ["target_entity_id"], "respond": ["invite_id", "accept"], "remove": ["target_entity_id"]},
	MANAGE_TRADE: {"invite": ["target_entity_id"], "respond": ["invite_id", "accept"],
		"add_item": ["trade_id", "instance_id", "quantity"], "remove_item": ["trade_id", "instance_id"],
		"set_currency": ["trade_id", "currency"], "ready": ["trade_id"], "cancel": ["trade_id"]},
	MANAGE_PRODUCTION: {"start": ["station_id", "recipe_id", "quantity", "speed"], "pause": [], "resume": [], "cancel": []},
	MANAGE_MAIL: {"send": ["recipient", "subject", "body", "section"], "read": ["mail_id"], "delete": ["mail_id"]},
}
const ALLOWED_FIELDS: Array[StringName] = [
	&"action_id",
	&"action_kind",
	&"observation_revision",
	&"expires_at_msec",
	&"payload",
]

var action_id := ""
var action_kind: StringName = WAIT
var observation_revision := -1
var expires_at_msec := -1
var payload: Dictionary = {}


func _init(
	requested_action_id: String,
	requested_action_kind: StringName,
	requested_observation_revision: int,
	requested_expires_at_msec: int,
	requested_payload: Dictionary,
) -> void:
	action_id = requested_action_id
	action_kind = requested_action_kind
	observation_revision = requested_observation_revision
	expires_at_msec = requested_expires_at_msec
	payload = requested_payload.duplicate(true)


static func wait_action(
	requested_action_id: String,
	requested_observation_revision: int,
	requested_expires_at_msec: int,
) -> HighLevelPlayerAction:
	return HighLevelPlayerAction.new(
		requested_action_id,
		WAIT,
		requested_observation_revision,
		requested_expires_at_msec,
		{},
	)


static func travel_to_area(
	requested_action_id: String,
	requested_observation_revision: int,
	requested_expires_at_msec: int,
	area_id: String,
) -> HighLevelPlayerAction:
	return HighLevelPlayerAction.new(
		requested_action_id,
		TRAVEL_TO_AREA,
		requested_observation_revision,
		requested_expires_at_msec,
		{"area_id": area_id},
	)


static func hunt_monster(
	requested_action_id: String,
	requested_observation_revision: int,
	requested_expires_at_msec: int,
	species_id: String,
	combat_mode := "stationary",
) -> HighLevelPlayerAction:
	return HighLevelPlayerAction.new(
		requested_action_id,
		HUNT_MONSTER,
		requested_observation_revision,
		requested_expires_at_msec,
		{"species_id": species_id, "combat_mode": combat_mode},
	)


static func gather_mine(
	requested_action_id: String,
	requested_observation_revision: int,
	requested_expires_at_msec: int,
	source_entity_id: String,
) -> HighLevelPlayerAction:
	return HighLevelPlayerAction.new(
		requested_action_id,
		GATHER_MINE,
		requested_observation_revision,
		requested_expires_at_msec,
		{"source_entity_id": source_entity_id},
	)


static func pickup_loot(
	requested_action_id: String,
	requested_observation_revision: int,
	requested_expires_at_msec: int,
	loot_id: String,
) -> HighLevelPlayerAction:
	return HighLevelPlayerAction.new(
		requested_action_id,
		PICKUP_LOOT,
		requested_observation_revision,
		requested_expires_at_msec,
		{"loot_id": loot_id},
	)


static func manage_objective(
	requested_action_id: String,
	requested_observation_revision: int,
	requested_expires_at_msec: int,
	objective_id: String,
	provider_id: String,
	operation: String,
) -> HighLevelPlayerAction:
	return HighLevelPlayerAction.new(
		requested_action_id,
		MANAGE_OBJECTIVE,
		requested_observation_revision,
		requested_expires_at_msec,
		{"objective_id": objective_id, "provider_id": provider_id, "operation": operation},
	)


static func send_chat(
	requested_action_id: String,
	requested_observation_revision: int,
	requested_expires_at_msec: int,
	channel: String,
	message: String,
	target_entity_id: String = "",
) -> HighLevelPlayerAction:
	var requested_payload := {"channel": channel, "message": message}
	if channel == "private":
		requested_payload["target_entity_id"] = target_entity_id
	return HighLevelPlayerAction.new(
		requested_action_id,
		SEND_CHAT,
		requested_observation_revision,
		requested_expires_at_msec,
		requested_payload,
	)


static func manage_party(
	requested_action_id: String,
	requested_observation_revision: int,
	requested_expires_at_msec: int,
	operation: String,
	target_entity_id: String = "",
	invite_id: String = "",
	accept: bool = false,
) -> HighLevelPlayerAction:
	var requested_payload := {"operation": operation}
	if operation in ["invite", "apply", "kick", "transfer_leader"]:
		requested_payload["target_entity_id"] = target_entity_id
	elif operation == "respond":
		requested_payload["invite_id"] = invite_id
		requested_payload["accept"] = accept
	return HighLevelPlayerAction.new(
		requested_action_id,
		MANAGE_PARTY,
		requested_observation_revision,
		requested_expires_at_msec,
		requested_payload,
	)


static func manage_trade(
	requested_action_id: String,
	requested_observation_revision: int,
	requested_expires_at_msec: int,
	operation: String,
	target_entity_id: String = "",
	invite_id: String = "",
	accept: bool = false,
	trade_id: String = "",
	instance_id: String = "",
	quantity: int = 0,
	currency: int = 0,
) -> HighLevelPlayerAction:
	var requested_payload := {"operation": operation}
	if operation == "invite":
		requested_payload["target_entity_id"] = target_entity_id
	elif operation == "respond":
		requested_payload["invite_id"] = invite_id
		requested_payload["accept"] = accept
	elif operation in ["add_item", "remove_item", "set_currency", "ready", "cancel"]:
		requested_payload["trade_id"] = trade_id
		if operation == "add_item":
			requested_payload["instance_id"] = instance_id
			requested_payload["quantity"] = quantity
		elif operation == "remove_item":
			requested_payload["instance_id"] = instance_id
		elif operation == "set_currency":
			requested_payload["currency"] = currency
	return HighLevelPlayerAction.new(
		requested_action_id,
		MANAGE_TRADE,
		requested_observation_revision,
		requested_expires_at_msec,
		requested_payload,
	)


func validate() -> DomainResult:
	if action_id.is_empty() or action_id.length() > Protocol.MAX_IDENTIFIER_LENGTH:
		return Result.failure(&"llm.action_invalid", "action_id is invalid")
	if observation_revision < 0:
		return Result.failure(&"llm.action_invalid", "observation_revision is invalid")
	if expires_at_msec <= 0:
		return Result.failure(&"llm.action_invalid", "expires_at_msec is invalid")
	if action_kind not in [WAIT, TRAVEL_TO_AREA, HUNT_MONSTER, GATHER_MINE, HARVEST_FRUIT, SELF_REPAIR, RETURN_TO_BASE, PICKUP_LOOT, MANAGE_OBJECTIVE, SEND_CHAT, MANAGE_PARTY, MANAGE_FRIEND, MANAGE_TRADE, TRADE_WITH_NPC, USE_ITEM, EQUIP_ITEM, SPLIT_ITEM, MERGE_ITEMS, MANAGE_PRODUCTION, MANAGE_MAIL]:
		return Result.failure(&"llm.action_unsupported", "action kind is not supported")
	if action_kind in [WAIT, SELF_REPAIR, RETURN_TO_BASE] and not payload.is_empty():
		return Result.failure(&"llm.action_invalid", "action cannot carry payload")
	if action_kind in [USE_ITEM, EQUIP_ITEM, SPLIT_ITEM, MERGE_ITEMS]:
		var expected_fields: Array[String] = ["instance_id"]
		if action_kind == SPLIT_ITEM:
			expected_fields.append("quantity")
		elif action_kind == MERGE_ITEMS:
			expected_fields.append("target_instance_id")
		if payload.size() != expected_fields.size():
			return Result.failure(&"llm.action_invalid", "item action contains the wrong fields")
		for field: String in expected_fields:
			if field != "quantity" and (typeof(payload.get(field)) != TYPE_STRING \
					or String(payload[field]).is_empty()):
				return Result.failure(&"llm.action_invalid", field + " is invalid")
		var quantity: Variant = payload.get("quantity")
		if action_kind == SPLIT_ITEM and (typeof(quantity) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(quantity)) or float(quantity) != float(int(quantity)) \
				or int(quantity) <= 0):
			return Result.failure(&"llm.action_invalid", "quantity must be positive")
	var target_fields := {TRAVEL_TO_AREA: "area_id", HUNT_MONSTER: "species_id", GATHER_MINE: "source_entity_id", HARVEST_FRUIT: "plant_id", PICKUP_LOOT: "loot_id"}
	if target_fields.has(action_kind):
		var field: String = target_fields[action_kind]
		var target: Variant = payload.get(field)
		if payload.size() != (2 if action_kind == HUNT_MONSTER else 1) or not target is String or target.is_empty() or target.length() > Protocol.MAX_IDENTIFIER_LENGTH:
			return Result.failure(&"llm.action_invalid", "action requires a valid " + field)
	if action_kind == HUNT_MONSTER and payload.get("combat_mode") not in COMBAT_MODES:
		return Result.failure(&"llm.action_invalid", "combat_mode must be stationary, shuttle or hexagon")
	if action_kind == MANAGE_OBJECTIVE:
		if payload.size() != 3:
			return Result.failure(&"llm.action_invalid", "objective action requires objective, provider and operation")
		for field: String in ["objective_id", "provider_id", "operation"]:
			var value := String(payload.get(field, ""))
			if value.is_empty() or value.length() > Protocol.MAX_IDENTIFIER_LENGTH:
				return Result.failure(&"llm.action_invalid", "%s is invalid" % field)
		if String(payload["operation"]) not in ["accept", "turn_in", "abandon"]:
			return Result.failure(&"llm.action_invalid", "objective operation is unsupported")
	if action_kind == SEND_CHAT:
		var channel := String(payload.get("channel", ""))
		var required_size := 3 if channel == "private" else 2
		if channel not in ["area", "party", "private"] or payload.size() != required_size:
			return Result.failure(&"llm.action_invalid", "chat action has an invalid channel or field set")
		var message := String(payload.get("message", "")).strip_edges()
		if message.is_empty() or message.length() > 200 or "\n" in message or "\r" in message:
			return Result.failure(&"llm.action_invalid", "chat message must be 1..200 characters on one line")
		if channel == "private":
			var target_entity_id := String(payload.get("target_entity_id", ""))
			if target_entity_id.is_empty() or target_entity_id.length() > Protocol.MAX_IDENTIFIER_LENGTH:
				return Result.failure(&"llm.action_invalid", "target_entity_id is invalid")
	if OPERATION_FIELDS.has(action_kind):
		var operation: Variant = payload.get("operation")
		var fields: Variant = OPERATION_FIELDS[action_kind].get(operation) if operation is String else null
		if fields == null or payload.size() != fields.size() + 1:
			return Result.failure(&"llm.action_invalid", "operation has an invalid field set")
		for field: String in fields:
			var value: Variant = payload.get(field)
			if field == "accept":
				if not value is bool: return Result.failure(&"llm.action_invalid", "accept must be boolean")
			elif field in ["quantity", "currency", "speed"]:
				if not value is int or value < (0 if field == "currency" else 1):
					return Result.failure(&"llm.action_invalid", field + " is invalid")
			else:
				var maximum := 1000 if field == "body" else 60 if field == "subject" else Protocol.MAX_IDENTIFIER_LENGTH
				if not value is String or value.strip_edges().is_empty() or value.length() > maximum:
					return Result.failure(&"llm.action_invalid", field + " is invalid")
				if field == "section" and value not in ["mail", "leaveword"]:
					return Result.failure(&"llm.action_invalid", "mail section is invalid")
				if field == "subject" and ("\n" in value or "\r" in value):
					return Result.failure(&"llm.action_invalid", "mail subject must be on one line")
	if action_kind == TRADE_WITH_NPC:
		var merchant_id := String(payload.get("merchant_id", ""))
		var operation := String(payload.get("operation", ""))
		if merchant_id.is_empty() or merchant_id.length() > Protocol.MAX_IDENTIFIER_LENGTH:
			return Result.failure(&"llm.action_invalid", "merchant_id is invalid")
		if operation == "buy":
			var display_name := String(payload.get("display_name", ""))
			if payload.size() != 3 or display_name.is_empty() \
					or display_name.length() > Protocol.MAX_IDENTIFIER_LENGTH:
				return Result.failure(&"llm.action_invalid", "NPC purchase requires merchant_id and display_name")
		elif operation == "sell":
			var instance_id := String(payload.get("instance_id", ""))
			if payload.size() != 4 or instance_id.is_empty() \
					or instance_id.length() > Protocol.MAX_IDENTIFIER_LENGTH \
					or typeof(payload.get("quantity")) != TYPE_INT or int(payload["quantity"]) <= 0:
				return Result.failure(&"llm.action_invalid", "NPC sale requires an item and positive quantity")
		else:
			return Result.failure(&"llm.action_invalid", "NPC trade operation is unsupported")
	return Result.ok(self)


func to_dictionary() -> Dictionary:
	return {
		"action_id": action_id,
		"action_kind": String(action_kind),
		"observation_revision": observation_revision,
		"expires_at_msec": expires_at_msec,
		"payload": payload.duplicate(true),
	}


static func from_dictionary(raw: Variant) -> DomainResult:
	if not raw is Dictionary:
		return Result.failure(&"llm.action_invalid", "action must be a Dictionary")
	var source: Dictionary = raw
	for key: Variant in source.keys():
		if StringName(key) not in ALLOWED_FIELDS:
			return Result.failure(&"llm.action_invalid", "action contains an unknown field")
	var action := HighLevelPlayerAction.new(
		String(source.get("action_id", "")),
		StringName(source.get("action_kind", "")),
		int(source.get("observation_revision", -1)),
		int(source.get("expires_at_msec", -1)),
		source.get("payload", {}) if source.get("payload", {}) is Dictionary else {},
	)
	var validation := action.validate()
	return Result.ok(action) if validation.is_ok else validation
