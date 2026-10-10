class_name ProgrammaticActionExecutor
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")
const MoveIntentContract = preload("res://scripts/network/contracts/move_intent.gd")
const HighLevelPlayerActionScript = preload("res://scripts/server/llm/high_level_player_action.gd")
const PlayerIntentScript = preload("res://scripts/server/llm/player_intent.gd")

var actor_id := ""
var _area_resolver: Callable
var _latest_observation: PlayerObservation
var _latest_observation_revision := -1
var _next_sequence := 1
var _accepted_action_ids: Dictionary = {}


func configure(requested_actor_id: String, area_resolver: Callable) -> DomainResult:
	if requested_actor_id.is_empty() or not area_resolver.is_valid():
		return Result.failure(&"llm.executor_invalid", "actor and area resolver are required")
	actor_id = requested_actor_id
	_area_resolver = area_resolver
	return Result.ok(self)


func accept_observation(observation: PlayerObservation) -> DomainResult:
	if observation == null or observation.actor_id != actor_id:
		return Result.failure(&"llm.observation_actor_mismatch", "observation belongs to another actor")
	if observation.observation_revision < _latest_observation_revision:
		return Result.failure(&"llm.observation_stale", "observation revision is older than the current frame")
	_latest_observation = observation
	_latest_observation_revision = observation.observation_revision
	return Result.ok(observation)


func execute(raw_action: Variant, now_msec := -1) -> DomainResult:
	if _latest_observation == null:
		return Result.failure(&"llm.observation_required", "an observation is required before acting")
	var action_result := _action_from_variant(raw_action)
	if not action_result.is_ok:
		return action_result
	var action: HighLevelPlayerAction = action_result.value
	if action.action_id in _accepted_action_ids:
		return Result.failure(&"llm.action_duplicate", "action_id was already accepted")
	if action.observation_revision != _latest_observation_revision:
		return Result.failure(&"llm.observation_stale", "action references an old observation")
	var current_time := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	if current_time >= action.expires_at_msec:
		return Result.failure(&"llm.action_expired", "action expiry was reached")
	var intent_result := _build_intent(action)
	if not intent_result.is_ok:
		return intent_result
	_accepted_action_ids[action.action_id] = current_time
	return intent_result


func _action_from_variant(raw_action: Variant) -> DomainResult:
	if raw_action is HighLevelPlayerAction:
		var action: HighLevelPlayerAction = raw_action
		var validation := action.validate()
		return Result.ok(action) if validation.is_ok else validation
	return HighLevelPlayerActionScript.from_dictionary(raw_action)


func _build_intent(action: HighLevelPlayerAction) -> DomainResult:
	var sequence := _next_sequence
	_next_sequence += 1
	if action.action_kind == HighLevelPlayerActionScript.WAIT:
		return Result.ok(PlayerIntentScript.new(
			actor_id,
			&"wait",
			sequence,
			action.observation_revision,
			{},
		))
	if action.action_kind in [HighLevelPlayerActionScript.SELF_REPAIR, HighLevelPlayerActionScript.RETURN_TO_BASE]:
		return Result.ok(PlayerIntentScript.new(
			actor_id, &"self_repair" if action.action_kind == HighLevelPlayerActionScript.SELF_REPAIR else &"recovery", sequence, action.observation_revision, {},
		))
	if action.action_kind in [HighLevelPlayerActionScript.MANAGE_PRODUCTION, HighLevelPlayerActionScript.MANAGE_MAIL]:
		return Result.ok(PlayerIntentScript.new(actor_id,
			&"production" if action.action_kind == HighLevelPlayerActionScript.MANAGE_PRODUCTION else &"mail",
			sequence, action.observation_revision, action.payload))
	if action.action_kind == HighLevelPlayerActionScript.PICKUP_LOOT:
		var loot_id := String(action.payload["loot_id"])
		for item: Dictionary in _latest_observation.ground_items:
			if String(item.get("loot_id", "")) == loot_id:
				return Result.ok(PlayerIntentScript.new(
					actor_id,
					&"loot",
					sequence,
					action.observation_revision,
					{"loot_id": loot_id},
				))
		return Result.failure(&"llm.loot_unavailable", "ground item is not in the current observation")
	if action.action_kind in [HighLevelPlayerActionScript.USE_ITEM, HighLevelPlayerActionScript.EQUIP_ITEM, HighLevelPlayerActionScript.SPLIT_ITEM, HighLevelPlayerActionScript.MERGE_ITEMS]:
		var payload := action.payload.duplicate(true)
		payload["type"] = {
			HighLevelPlayerActionScript.USE_ITEM: "use_inventory_item",
			HighLevelPlayerActionScript.EQUIP_ITEM: "equip_item",
			HighLevelPlayerActionScript.SPLIT_ITEM: "split_inventory_item",
			HighLevelPlayerActionScript.MERGE_ITEMS: "merge_inventory_item",
		}[action.action_kind]
		return Result.ok(PlayerIntentScript.new(
			actor_id, &"panel_command", sequence, action.observation_revision, payload,
		))
	if action.action_kind == HighLevelPlayerActionScript.TRADE_WITH_NPC:
		var merchant_id := String(action.payload["merchant_id"])
		var operation := String(action.payload["operation"])
		for shop: Dictionary in _latest_observation.npc_shops:
			if String(shop.get("merchant_id", "")) != merchant_id:
				continue
			if operation == "buy":
				var display_name := String(action.payload["display_name"])
				var definition_id := ""
				for offer: Dictionary in shop.get("offers", []):
					if String(offer.get("display_name", "")) != display_name:
						continue
					if not definition_id.is_empty():
						return Result.failure(&"commerce.offer_ambiguous", "NPC merchant has multiple items with that name")
					definition_id = String(offer.get("definition_id", ""))
				if definition_id.is_empty():
					return Result.failure(&"commerce.item_not_offered", "NPC merchant does not sell that item")
				return Result.ok(PlayerIntentScript.new(
					actor_id, &"npc_trade", sequence, action.observation_revision,
					{"merchant_id": merchant_id, "operation": operation, "definition_id": definition_id},
				))
			var instance_id := String(action.payload["instance_id"])
			var requested_quantity := int(action.payload["quantity"])
			for item: Dictionary in shop.get("sellable_items", []):
				if String(item.get("instance_id", "")) == instance_id:
					if requested_quantity > int(item.get("quantity", 0)):
						return Result.failure(&"inventory.quantity_invalid", "sale quantity exceeds the observed stack")
					return Result.ok(PlayerIntentScript.new(
						actor_id, &"npc_trade", sequence, action.observation_revision,
						action.payload.duplicate(true),
					))
			return Result.failure(&"commerce.item_not_sellable", "item is not sellable to this NPC merchant")
		return Result.failure(&"commerce.merchant_not_here", "NPC shop is not in the current observation")
	if action.action_kind == HighLevelPlayerActionScript.HUNT_MONSTER:
		var species_id := String(action.payload["species_id"])
		for species: Dictionary in _latest_observation.hunt_options:
			if String(species.get("species_id", "")) == species_id:
				return Result.ok(PlayerIntentScript.new(
					actor_id,
					&"hunt",
					sequence,
					action.observation_revision,
					action.payload,
				))
		return Result.failure(&"llm.target_unavailable", "hunt species is not available in the current observation")
	if action.action_kind == HighLevelPlayerActionScript.GATHER_MINE:
		var source_id := String(action.payload["source_entity_id"])
		for entity: Dictionary in _latest_observation.visible_entities:
			if String(entity.get("entity_id", "")) != source_id:
				continue
			if String(entity.get("entity_kind", "")) != "mine_source" \
					or not bool(entity.get("alive", false)) or int(entity.get("remaining", 0)) <= 0:
				return Result.failure(&"llm.source_unavailable", "gather source is not an available visible mine")
			return Result.ok(PlayerIntentScript.new(
				actor_id,
				&"gather",
				sequence,
				action.observation_revision,
				{"source_entity_id": source_id},
			))
		return Result.failure(&"llm.source_unavailable", "gather source is not in the current observation")
	if action.action_kind == HighLevelPlayerActionScript.HARVEST_FRUIT:
		var plant_id := String(action.payload["plant_id"])
		for facility: Dictionary in _latest_observation.facilities:
			if String(facility.get("entity_id", "")) != plant_id:
				continue
			if String(facility.get("facility_kind", "")) != "garden_plant":
				return Result.failure(&"garden.not_a_plant", "目标不是可采摘的果实")
			if not bool(facility.get("available", false)):
				return Result.failure(&"garden.regrowing", "果实尚未成熟")
			return Result.ok(PlayerIntentScript.new(
				actor_id,
				&"harvest",
				sequence,
				action.observation_revision,
				{"plant_id": plant_id},
			))
		return Result.failure(&"garden.plant_missing", "果实不在当前观察中")
	if action.action_kind == HighLevelPlayerActionScript.MANAGE_OBJECTIVE:
		var objective_id := String(action.payload["objective_id"])
		for objective: Dictionary in _latest_observation.available_objectives:
			if String(objective.get("objective_id", "")) != objective_id:
				continue
			if String(objective.get("provider_id", "")) != String(action.payload["provider_id"]):
				return Result.failure(&"llm.objective_unavailable", "objective provider does not match the observation")
			return Result.ok(PlayerIntentScript.new(
				actor_id,
				&"objective",
				sequence,
				action.observation_revision,
				{
					"objective_id": objective_id,
					"provider_id": String(action.payload["provider_id"]),
					"operation": String(action.payload["operation"]),
				},
			))
		return Result.failure(&"llm.objective_unavailable", "objective is not in the current observation")
	if action.action_kind == HighLevelPlayerActionScript.SEND_CHAT:
		return Result.ok(PlayerIntentScript.new(
			actor_id,
			&"chat",
			sequence,
			action.observation_revision,
			action.payload,
		))
	if action.action_kind in [HighLevelPlayerActionScript.MANAGE_FRIEND, HighLevelPlayerActionScript.MANAGE_PARTY, HighLevelPlayerActionScript.MANAGE_TRADE]:
		var kind := String(action.action_kind).trim_prefix("manage_")
		var operation := String(action.payload["operation"])
		var state: Dictionary = _latest_observation.get(kind + "_state")
		var candidates: Array = _latest_observation.visible_entities
		var key := "entity_id"
		var requested_field := "target_entity_id"
		var error_code := StringName("llm." + kind + "_target_unavailable")
		if operation == "respond":
			candidates = state.get("pending_invites", [])
			key = "invite_id"
			requested_field = key
			error_code = StringName("llm." + kind + "_invite_unavailable")
		elif kind == "friend" and operation == "remove":
			candidates = state.get("friends", [])
			error_code = &"llm.friend_unavailable"
		elif kind == "party" and operation in ["kick", "transfer_leader"]:
			candidates = state.get("members", [])
		elif kind == "party" and operation == "leave":
			return Result.ok(PlayerIntentScript.new(actor_id, StringName(kind), sequence, action.observation_revision, action.payload))
		elif kind == "trade" and operation != "invite":
			var trade: Dictionary = state.get("trade", {})
			if String(trade.get("trade_id", "")) != String(action.payload["trade_id"]):
				return Result.failure(&"llm.trade_unavailable", "trade is not in the current observation")
			if operation not in ["add_item", "remove_item"]:
				return Result.ok(PlayerIntentScript.new(actor_id, &"trade", sequence, action.observation_revision, action.payload))
			var own_offer: Dictionary = trade.get("offers", {}).get(actor_id, {})
			candidates = _latest_observation.tradable_items if operation == "add_item" else own_offer.get("items", [])
			key = "instance_id"
			requested_field = key
			error_code = &"llm.trade_item_unavailable"
		for candidate: Dictionary in candidates:
			if String(candidate.get(key, "")) != String(action.payload[requested_field]): continue
			if operation in ["invite", "apply"] and String(candidate.get("entity_kind", "")) in ["monster", "mine_source"]:
				return Result.failure(error_code, "social target is not a player")
			if operation == "add_item" and int(action.payload["quantity"]) > int(candidate.get("quantity", 0)):
				return Result.failure(error_code, "trade quantity exceeds the observed item quantity")
			return Result.ok(PlayerIntentScript.new(actor_id, StringName(kind), sequence, action.observation_revision, action.payload))
		return Result.failure(error_code, "target is not in the current observation")
	if action.action_kind != HighLevelPlayerActionScript.TRAVEL_TO_AREA:
		return Result.failure(&"llm.action_unsupported", "programmatic executor does not support this action")
	var area_result = _area_resolver.call(
		String(action.payload["area_id"]),
		_latest_observation.internal_dictionary(),
	)
	if not area_result is DomainResult or not area_result.is_ok:
		return area_result if area_result is DomainResult else Result.failure(
			&"llm.area_unresolved", "area resolver returned an invalid result"
		)
	var destination: Dictionary = area_result.value if area_result.value is Dictionary else {}
	var map_instance_id := String(destination.get("map_instance_id", _latest_observation.map_instance_id))
	var target: Variant = destination.get("target_position", null)
	if map_instance_id.is_empty() or not target is Vector2 or not target.is_finite():
		return Result.failure(&"llm.area_unresolved", "area resolver returned an invalid destination")
	if map_instance_id == _latest_observation.map_instance_id:
		var move_contract := MoveIntentContract.new(map_instance_id, target, sequence)
		var validation: DomainResult = move_contract.validate()
		if not validation.is_ok:
			return Result.failure(&"llm.intent_invalid", validation.error_message)
		return Result.ok(PlayerIntentScript.new(
			actor_id,
			&"move",
			sequence,
			action.observation_revision,
			move_contract.to_dictionary(),
		))
	var transition_id := String(destination.get("transition_id", ""))
	var destination_entry_number := int(destination.get("destination_entry_number", -1))
	if transition_id.is_empty() or destination_entry_number < 0:
		return Result.failure(&"llm.transition_unresolved", "cross-map destination requires an authoritative transition")
	var approach_contract := MoveIntentContract.new(_latest_observation.map_instance_id, target, sequence)
	var validation: DomainResult = approach_contract.validate()
	if not validation.is_ok:
		return Result.failure(&"llm.intent_invalid", validation.error_message)
	return Result.ok(PlayerIntentScript.new(
		actor_id,
		&"travel",
		sequence,
		action.observation_revision,
		{
			"map_instance_id": _latest_observation.map_instance_id,
			"requested_world_point": approach_contract.to_dictionary()["requested_world_point"],
			"transition_id": transition_id,
			"destination_entry_number": destination_entry_number,
			"destination_map_instance_id": map_instance_id,
		},
	))
