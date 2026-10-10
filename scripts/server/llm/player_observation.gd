class_name PlayerObservation
extends RefCounted

var actor_id := ""
var observation_revision := -1
var map_instance_id := ""
var map_id := ""
var self_state: Dictionary = {}
var visible_entities: Array[Dictionary] = []
var hunt_options: Array[Dictionary] = []
var available_objectives: Array[Dictionary] = []
var party_state: Dictionary = {}
var friend_state: Dictionary = {}
var trade_state: Dictionary = {}
var available_transitions: Array[Dictionary] = []
var ground_items: Array[Dictionary] = []
var npcs: Array[Dictionary] = []
var facilities: Array[Dictionary] = []
var npc_shops: Array[Dictionary] = []
var tradable_items: Array[Dictionary] = []
var character_panel: Dictionary = {}
var vehicle_panel: Dictionary = {}
var inventory_panel: Dictionary = {}
var navigation_state: Dictionary = {}
var recent_events: Array[Dictionary] = []
var captured_at_msec := 0


func _init(
	requested_actor_id: String,
	requested_observation_revision: int,
	requested_map_instance_id: String,
	requested_map_id: String,
	requested_self_state: Dictionary,
	requested_visible_entities: Array[Dictionary],
	requested_available_objectives: Array[Dictionary],
	requested_recent_events: Array[Dictionary],
	requested_captured_at_msec: int,
	requested_party_state: Dictionary = {},
	requested_trade_state: Dictionary = {},
	requested_available_transitions: Array[Dictionary] = [],
	requested_hunt_options: Array[Dictionary] = [],
	requested_ground_items: Array[Dictionary] = [],
	requested_npcs: Array[Dictionary] = [],
	requested_facilities: Array[Dictionary] = [],
	requested_npc_shops: Array[Dictionary] = [],
	requested_tradable_items: Array[Dictionary] = [],
	requested_character_panel: Dictionary = {},
	requested_vehicle_panel: Dictionary = {},
	requested_inventory_panel: Dictionary = {},
	requested_navigation_state: Dictionary = {},
	requested_friend_state: Dictionary = {},
) -> void:
	actor_id = requested_actor_id
	observation_revision = requested_observation_revision
	map_instance_id = requested_map_instance_id
	map_id = requested_map_id
	self_state = requested_self_state.duplicate(true)
	visible_entities = requested_visible_entities.duplicate(true)
	hunt_options = requested_hunt_options.duplicate(true)
	available_objectives = requested_available_objectives.duplicate(true)
	party_state = requested_party_state.duplicate(true)
	friend_state = requested_friend_state.duplicate(true)
	trade_state = requested_trade_state.duplicate(true)
	available_transitions = requested_available_transitions.duplicate(true)
	ground_items = requested_ground_items.duplicate(true)
	npcs = requested_npcs.duplicate(true)
	facilities = requested_facilities.duplicate(true)
	npc_shops = requested_npc_shops.duplicate(true)
	tradable_items = requested_tradable_items.duplicate(true)
	character_panel = requested_character_panel.duplicate(true)
	vehicle_panel = requested_vehicle_panel.duplicate(true)
	inventory_panel = requested_inventory_panel.duplicate(true)
	navigation_state = requested_navigation_state.duplicate(true)
	recent_events = requested_recent_events.duplicate(true)
	captured_at_msec = requested_captured_at_msec


func to_dictionary() -> Dictionary:
	return {
		"map_id": map_id,
		"self": self_state.duplicate(true),
		"visible_entities": visible_entities.duplicate(true),
		"hunt_options": hunt_options.duplicate(true),
		"available_objectives": available_objectives.duplicate(true),
		"party_state": party_state.duplicate(true),
		"friend_state": friend_state.duplicate(true),
		"trade_state": trade_state.duplicate(true),
		"available_transitions": available_transitions.duplicate(true),
		"recent_events": recent_events.duplicate(true),
	}


func internal_dictionary() -> Dictionary:
	var result := to_dictionary()
	result["actor_id"] = actor_id
	result["observation_revision"] = observation_revision
	result["map_instance_id"] = map_instance_id
	var internal_self := self_state.duplicate(true)
	internal_self["position"] = navigation_state.get("position", [])
	result["self"] = internal_self
	return result
