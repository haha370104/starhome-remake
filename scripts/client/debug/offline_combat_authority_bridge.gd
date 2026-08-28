class_name OfflineCombatAuthorityBridge
extends Node

const CombatCatalogScript := preload("res://scripts/domain/combat/combat_definition_catalog.gd")
const CombatModuleScript := preload("res://scripts/server/modules/combat/authoritative_combat_module.gd")
const UseAbilityIntentScript := preload("res://scripts/network/contracts/use_ability_intent.gd")

signal combat_snapshot_ready(snapshot: Dictionary)
signal combat_event_ready(event: Dictionary)

const SIMULATION_HZ := 20
const SNAPSHOT_INTERVAL_TICKS := 2
const LOCAL_ACTOR_ID := "player.local"
const ABILITY_ID := "energy_cannon.primary"

var module: AuthoritativeCombatModule
var navigation
var map_instance_id := ""
var player_position := Vector2.ZERO
var _accumulator := 0.0
var _next_command_sequence := 1


## Rebuilds the debug authority for [param map_id] and [param requested_map_instance_id].
## [param map_id] Active business map whose configured encounter is loaded.
## [param requested_map_instance_id] Local debug instance identity matching client intents.
## [param requested_player_position] Current player foot point registered as an authority actor.
## [param requested_navigation] Loaded immutable navigation used to admit AI movement.
## Returns `OK`; maps without encounters simply clear combat state.
## Design: This is an in-process dedicated-server substitute for editor testing, not client-owned combat arithmetic.
func configure_map(
	map_id: String,
	requested_map_instance_id: String,
	requested_player_position: Vector2,
	requested_navigation,
) -> Error:
	module = null
	navigation = requested_navigation
	map_instance_id = requested_map_instance_id
	player_position = requested_player_position
	_accumulator = 0.0
	_next_command_sequence = 1
	var catalog_result = CombatCatalogScript.load_default()
	if not catalog_result.is_ok:
		return ERR_INVALID_DATA
	var catalog = catalog_result.value
	var monsters_result = catalog.monster_lifecycles_for_map(map_id, map_instance_id)
	if not monsters_result.is_ok:
		return ERR_INVALID_DATA
	if monsters_result.value.is_empty():
		combat_snapshot_ready.emit({"server_tick": 0, "local_vehicle": {}, "monsters": []})
		return OK
	var assembly_result = catalog.starter_vehicle_assembly(10, {
		"base_speed_multiplier": 1500.0,
		"base_speed_cap": 240.0,
	})
	var weapon_result = catalog.starter_energy_cannon(SIMULATION_HZ)
	if not assembly_result.is_ok or not weapon_result.is_ok:
		return ERR_INVALID_DATA
	module = CombatModuleScript.new()
	if not module.configure(SIMULATION_HZ, hash(map_instance_id), 1.0).is_ok:
		return ERR_INVALID_DATA
	module.set_monster_position_resolver(_resolve_monster_position)
	if not module.register_vehicle(
		LOCAL_ACTOR_ID,
		map_instance_id,
		player_position,
		assembly_result.value,
		{ABILITY_ID: weapon_result.value},
	).is_ok:
		return ERR_INVALID_DATA
	for raw_definition: Variant in monsters_result.value:
		var definition: Dictionary = raw_definition.duplicate(true)
		definition["position"] = _walkable_position(definition["position"])
		if not module.register_monster(definition).is_ok:
			return ERR_INVALID_DATA
	_emit_snapshot()
	return OK


## Updates the authority-owned actor coordinate from validated local navigation [param position].
## [param position] Current player foot point already admitted by `LocalPlayerController`.
func update_player_position(position: Vector2) -> void:
	player_position = position
	if module != null:
		module.update_actor_position(LOCAL_ACTOR_ID, position)


## Submits one target-only attack against [param target_entity_id].
## [param target_entity_id] Monster identity selected from the latest authority snapshot.
## Returns the authoritative event or a stable local-debug error dictionary.
func request_attack(target_entity_id: String) -> Dictionary:
	if module == null or target_entity_id.is_empty():
		return {"ok": false, "code": &"combat.no_target"}
	var intent := UseAbilityIntentScript.new(
		map_instance_id, ABILITY_ID, target_entity_id, _next_command_sequence
	)
	_next_command_sequence += 1
	var result = module.handle_energy_cannon_attack(LOCAL_ACTOR_ID, intent.to_dictionary())
	if result.is_ok:
		combat_event_ready.emit(result.value.duplicate(true))
		_emit_snapshot()
		return {"ok": true, "value": result.value}
	return {"ok": false, "code": result.error_code, "message": result.error_message}


## Advances the in-process authority by fixed ticks derived from frame [param delta].
## [param delta] Frame time accumulated into the same 20 Hz simulation used by the server.
func _process(delta: float) -> void:
	if module == null or delta <= 0.0:
		return
	_accumulator += delta
	var fixed_delta := 1.0 / float(SIMULATION_HZ)
	while _accumulator + 0.000001 >= fixed_delta:
		_accumulator -= fixed_delta
		module.update_actor_position(LOCAL_ACTOR_ID, player_position)
		module.advance_ticks(1)
		if module.current_tick % SNAPSHOT_INTERVAL_TICKS == 0:
			_emit_snapshot()


## Emits the current map-scoped combat state to presentation consumers.
func _emit_snapshot() -> void:
	if module != null:
		combat_snapshot_ready.emit(module.snapshot_for_actor(LOCAL_ACTOR_ID))


## Resolves a walkable AI step from [param current_position] to [param requested_position].
## [param monster_id] Stable identity retained for parity with the production resolver signature.
## [param current_position] Existing authoritative monster foot point.
## [param requested_position] AI-selected next fixed-step coordinate.
## Returns a walkable point or the current point when navigation rejects the request.
func _resolve_monster_position(
	monster_id: String,
	current_position: Vector2,
	requested_position: Vector2,
) -> Vector2:
	if monster_id.is_empty() or navigation == null:
		return current_position
	if navigation.is_walkable(requested_position):
		return requested_position
	var fallback: Vector2 = navigation.closest_reachable_position(current_position, requested_position)
	return fallback if fallback.is_finite() else current_position


## Snaps [param requested_position] to immutable navigation for initial monster admission.
## [param requested_position] Configured spawn coordinate generated from the encounter group.
## Returns a finite walkable coordinate when possible.
func _walkable_position(requested_position: Vector2) -> Vector2:
	if navigation == null or navigation.is_walkable(requested_position):
		return requested_position
	return navigation.closest_walkable_position(requested_position)
