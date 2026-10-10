class_name ObservationPolicy
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")

const SELF_FIELDS: Array[StringName] = [
	&"display_name",
	&"comprehensive_level",
	&"residence",
	&"health",
	&"max_health",
	&"self_repair_active",
	&"reserve_energy",
	&"reserve_energy_capacity",
	&"working_energy",
	&"working_energy_capacity",
	&"inventory_used",
	&"inventory_capacity",
	&"currency",
]
const ENTITY_FIELDS: Array[StringName] = [
	&"entity_id",
	&"entity_kind",
	&"position",
	&"action_id",
	&"display_name",
	&"species_id",
	&"health",
	&"max_health",
	&"alive",
	&"remaining",
	&"mineral_id",
	&"required_mining_level",
]
const GROUND_ITEM_FIELDS: Array[StringName] = [
	&"loot_id",
	&"item_definition_id",
	&"display_name",
	&"quantity",
	&"position",
	&"player_dropped",
]
const NPC_FIELDS: Array[StringName] = [&"npc_id", &"display_name", &"npc_kind", &"position"]
const FACILITY_FIELDS: Array[StringName] = [
	&"facility_id", &"station_id", &"name", &"position", &"interaction_radius",
	&"entity_id", &"facility_kind", &"display_name", &"item_definition_id",
	&"available", &"remaining_seconds",
]
const NPC_SHOP_FIELDS: Array[StringName] = [&"merchant_id", &"merchant_name", &"currency"]
const NPC_OFFER_FIELDS: Array[StringName] = [
	&"definition_id", &"display_name", &"category", &"required_level", &"price",
]
const NPC_SELLABLE_FIELDS: Array[StringName] = [
	&"instance_id", &"definition_id", &"display_name", &"quantity", &"unit_price",
]
const OBJECTIVE_FIELDS: Array[StringName] = [
	&"objective_id",
	&"task_id",
	&"title",
	&"kind",
	&"provider_id",
	&"status",
	&"accepted",
	&"ready_to_turn_in",
	&"requirements",
	&"target",
	&"completions",
	&"maximum_completions",
	&"exhausted",
	&"daily_accepted",
	&"daily_accept_limit",
	&"skill_id",
	&"skill_level_reward",
]
const EVENT_FIELDS: Array[StringName] = [&"event_id", &"kind", &"message"]
const PARTY_FIELDS: Array[StringName] = [&"party_id", &"leader_id"]
const PARTY_MEMBER_FIELDS: Array[StringName] = [&"entity_id", &"display_name", &"connected"]
const PARTY_INVITE_FIELDS: Array[StringName] = [
	&"invite_id", &"party_id", &"request_type", &"inviter_id", &"inviter_name", &"target_entity_id",
]
const FRIEND_ENTRY_FIELDS: Array[StringName] = [
	&"entity_id", &"display_name", &"online", &"same_map",
]
const FRIEND_INVITE_FIELDS: Array[StringName] = [
	&"invite_id", &"inviter_id", &"inviter_name", &"target_entity_id",
]
const TRADE_FIELDS: Array[StringName] = [&"trade_id", &"members"]
const TRADE_OFFER_FIELDS: Array[StringName] = [&"entity_id", &"display_name", &"currency", &"locked"]
const TRADE_ITEM_FIELDS: Array[StringName] = [&"instance_id", &"definition_id", &"display_name", &"quantity"]
const TRADE_INVITE_FIELDS: Array[StringName] = [&"invite_id", &"inviter_id", &"inviter_name", &"target_entity_id"]
const TRANSITION_FIELDS: Array[StringName] = [
	&"transition_id", &"label", &"destination_key", &"destination_entry_number", &"approach_point",
]


static func public_value(value: Variant, actor_id: String) -> Variant:
	if value is Array:
		return value.map(func(entry: Variant) -> Variant: return public_value(entry, actor_id))
	if value is Dictionary:
		var projected := {}
		for raw_field: Variant in value:
			var field := String(raw_field)
			if field in ["actor_id", "character_id", "vehicle_id", "map_instance_id", "revision", "version", "schema_version", "source_required_skill_level", "sequence", "event_id", "message_id", "combat_event_id", "server_tick", "created_at_msec", "captured_at_msec"] or field.ends_with("_revision") or field.ends_with("_sequence"):
				continue
			projected["self" if field == actor_id else field] = public_value(value[raw_field], actor_id)
		return projected
	return "self" if value is String and value == actor_id else value


func build(authoritative_snapshot: Dictionary, role: StringName = &"llm") -> DomainResult:
	if role != &"llm":
		return Result.failure(&"observation.role_forbidden", "only the llm observation role is available")
	var actor_id := String(authoritative_snapshot.get("actor_id", ""))
	if actor_id.is_empty():
		return Result.failure(&"observation.actor_missing", "observation actor_id is required")
	var revision := int(authoritative_snapshot.get(
		"observation_revision", authoritative_snapshot.get("server_tick", -1)
	))
	if revision < 0:
		return Result.failure(&"observation.revision_missing", "observation revision is required")
	var map_instance_id := String(authoritative_snapshot.get("map_instance_id", ""))
	var map_id := String(authoritative_snapshot.get("map_id", ""))
	var raw_self: Dictionary = authoritative_snapshot.get("self", {})
	var self_state := _project(raw_self, SELF_FIELDS)
	var tradable_items := _project_items(raw_self.get("tradable_items", []))
	var panel_bundle: Dictionary = authoritative_snapshot.get("panel_bundle", {})
	var character_panel := _project_panel(panel_bundle.get("character", {}))
	var vehicle_panel := _project_panel(panel_bundle.get("vehicle", {}))
	var inventory_panel := _project_inventory(panel_bundle.get("inventory", {}))
	var visible_entities: Array[Dictionary] = []
	var monsters_by_species: Dictionary = {}
	for raw_entity: Variant in authoritative_snapshot.get("nearby_entities", []):
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		if String(entity.get("entity_id", "")) == actor_id:
			continue
		if bool(entity.get("hidden", false)):
			continue
		var visible_to: Variant = entity.get("visible_to", [])
		if visible_to is Array and not visible_to.is_empty() \
				and &"llm" not in visible_to and &"all" not in visible_to \
				and "llm" not in visible_to and "all" not in visible_to:
			continue
		if String(entity.get("entity_kind", "")) == "monster":
			var species_id := String(entity.get("species_id", ""))
			if species_id.is_empty() or not bool(entity.get("alive", false)):
				continue
			var species: Dictionary = monsters_by_species.get(species_id, {
				"species_id": species_id,
				"display_name": String(entity.get("display_name", species_id)),
				"available_count": 0,
			})
			species["available_count"] = int(species["available_count"]) + 1
			monsters_by_species[species_id] = species
			continue
		var projected := _project(entity, ENTITY_FIELDS)
		if not String(projected.get("entity_id", "")).is_empty():
			visible_entities.append(projected)
	var hunt_options: Array[Dictionary] = []
	var species_ids: Array = monsters_by_species.keys()
	species_ids.sort()
	for species_id: String in species_ids:
		hunt_options.append(monsters_by_species[species_id])
	var ground_items: Array[Dictionary] = []
	for raw_item: Variant in authoritative_snapshot.get("ground_items", []):
		if not raw_item is Dictionary:
			continue
		var projected_item := _project(raw_item, GROUND_ITEM_FIELDS)
		if not String(projected_item.get("loot_id", "")).is_empty():
			ground_items.append(projected_item)
	var npcs: Array[Dictionary] = []
	for raw_npc: Variant in authoritative_snapshot.get("npcs", []):
		if not raw_npc is Dictionary:
			continue
		var projected_npc := _project(raw_npc, NPC_FIELDS)
		if not String(projected_npc.get("npc_id", "")).is_empty():
			npcs.append(projected_npc)
	var facilities: Array[Dictionary] = []
	for raw_facility: Variant in authoritative_snapshot.get("facilities", []):
		if not raw_facility is Dictionary:
			continue
		var projected_facility := _project(raw_facility, FACILITY_FIELDS)
		if not String(projected_facility.get("facility_id", "")).is_empty():
			facilities.append(projected_facility)
	var npc_shops: Array[Dictionary] = []
	for raw_shop: Variant in authoritative_snapshot.get("npc_shops", []):
		if not raw_shop is Dictionary:
			continue
		var projected_shop := _project(raw_shop, NPC_SHOP_FIELDS)
		projected_shop["offers"] = _project_rows(raw_shop.get("offers", []), NPC_OFFER_FIELDS)
		projected_shop["sellable_items"] = _project_rows(
			raw_shop.get("sellable_items", []), NPC_SELLABLE_FIELDS
		)
		if not String(projected_shop.get("merchant_id", "")).is_empty():
			npc_shops.append(projected_shop)
	var objectives: Array[Dictionary] = []
	for raw_objective: Variant in authoritative_snapshot.get("available_objectives", []):
		if not raw_objective is Dictionary or bool(raw_objective.get("private", false)):
			continue
		objectives.append(_project(raw_objective, OBJECTIVE_FIELDS))
	var party_state := _project_party(authoritative_snapshot.get("party_state", {}))
	var friend_state := _project_friend(authoritative_snapshot.get("friend_state", {}))
	var trade_state := _project_trade(authoritative_snapshot.get("trade_state", {}))
	var available_transitions: Array[Dictionary] = []
	for raw_transition: Variant in authoritative_snapshot.get("available_transitions", []):
		if raw_transition is Dictionary:
			available_transitions.append(_project(raw_transition, TRANSITION_FIELDS))
	var events: Array[Dictionary] = []
	for raw_event: Variant in authoritative_snapshot.get("recent_events", []):
		if not raw_event is Dictionary or bool(raw_event.get("private", false)):
			continue
		events.append(_project(raw_event, EVENT_FIELDS))
	var captured_at_msec := int(authoritative_snapshot.get("captured_at_msec", Time.get_ticks_msec()))
	return Result.ok(PlayerObservation.new(
		actor_id,
		revision,
		map_instance_id,
		map_id,
		self_state,
		visible_entities,
		objectives,
		events,
		captured_at_msec,
		party_state,
		trade_state,
		available_transitions,
		hunt_options,
		ground_items,
		npcs,
		facilities,
		npc_shops,
		tradable_items,
		character_panel,
		vehicle_panel,
		inventory_panel,
		{"position": raw_self.get("position", [])},
		friend_state,
	))


func _project_items(raw_items: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_items is Array:
		return result
	for raw_item: Variant in raw_items:
		if raw_item is Dictionary:
			result.append(_project(raw_item, TRADE_ITEM_FIELDS))
	return result


func _project_rows(raw_rows: Variant, fields: Array[StringName]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_rows is Array:
		return result
	for raw_row: Variant in raw_rows:
		if raw_row is Dictionary:
			result.append(_project(raw_row, fields))
	return result


func _project_panel(raw_panel: Variant) -> Dictionary:
	if not raw_panel is Dictionary:
		return {}
	var result: Dictionary = raw_panel.duplicate(true)
	for field: String in ["revision", "transaction_revision", "character_id", "vehicle_id", "container_id"]:
		result.erase(field)
	if result.has("level") and not result.has("comprehensive_level"):
		result["comprehensive_level"] = result["level"]
	return result


func _project_inventory(raw_panel: Variant) -> Dictionary:
	if not raw_panel is Dictionary or raw_panel.is_empty():
		return {}
	return {"items": _project_rows(raw_panel.get("items", []), [
		&"instance_id", &"display_name", &"type", &"quantity",
	])}


func _project_trade(raw_trade_state: Variant) -> Dictionary:
	if not raw_trade_state is Dictionary:
		return {}
	var source: Dictionary = raw_trade_state
	var result := {"trade": {"trade_id": "", "members": [], "offers": {}}, "pending_invites": []}
	var raw_trade: Variant = source.get("trade", {})
	if raw_trade is Dictionary:
		var trade_source: Dictionary = raw_trade
		var trade: Dictionary = _project(trade_source, TRADE_FIELDS)
		trade["members"] = []
		for raw_member: Variant in trade_source.get("members", []):
			trade["members"].append(String(raw_member))
		var offers: Dictionary = {}
		for raw_entity_id: Variant in trade_source.get("offers", {}).keys():
			var raw_offer: Variant = trade_source.get("offers", {}).get(raw_entity_id, {})
			if not raw_offer is Dictionary:
				continue
			var offer: Dictionary = _project(raw_offer, TRADE_OFFER_FIELDS)
			offer["items"] = _project_items(raw_offer.get("items", []))
			offers[String(raw_entity_id)] = offer
		trade["offers"] = offers
		result["trade"] = trade
	for raw_invite: Variant in source.get("pending_invites", []):
		if raw_invite is Dictionary:
			result["pending_invites"].append(_project(raw_invite, TRADE_INVITE_FIELDS))
	return result


func _project_party(raw_party: Variant) -> Dictionary:
	if not raw_party is Dictionary:
		return {}
	var source: Dictionary = raw_party
	var result := _project(source, PARTY_FIELDS)
	var members: Array[Dictionary] = []
	for raw_member: Variant in source.get("members", []):
		if raw_member is Dictionary:
			members.append(_project(raw_member, PARTY_MEMBER_FIELDS))
	var pending_invites: Array[Dictionary] = []
	for raw_invite: Variant in source.get("pending_invites", []):
		if raw_invite is Dictionary:
			pending_invites.append(_project(raw_invite, PARTY_INVITE_FIELDS))
	result["members"] = members
	result["pending_invites"] = pending_invites
	return result


func _project_friend(raw_friend: Variant) -> Dictionary:
	if not raw_friend is Dictionary:
		return {"friends": [], "enemies": [], "pending_invites": []}
	var source: Dictionary = raw_friend
	return {
		"friends": _project_rows(source.get("friends", []), FRIEND_ENTRY_FIELDS),
		"enemies": _project_rows(source.get("enemies", []), FRIEND_ENTRY_FIELDS),
		"pending_invites": _project_rows(source.get("pending_invites", []), FRIEND_INVITE_FIELDS),
	}


func _project(source: Dictionary, fields: Array[StringName]) -> Dictionary:
	var result := {}
	for field: StringName in fields:
		if source.has(field):
			result[String(field)] = source[field]
	return result
