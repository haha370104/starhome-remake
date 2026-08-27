class_name MonsterLifecycle
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")

var monster_id := ""
var map_instance_id := ""
var position := Vector2.ZERO
var max_health := 0
var health := 0
var respawn_delay_ticks := 0
var respawn_at_tick := -1
var death_generation := 0
var last_killer_id := ""


## Configures this lifecycle from an injected monster [param definition].
## [param definition] Server definition containing identity, position, combat health and respawn seconds.
## [param simulation_hz] Fixed authoritative tick frequency used to derive the respawn deadline.
## Returns this lifecycle on success, otherwise a validation failure without a live monster.
func configure(definition: Dictionary, simulation_hz: int) -> DomainResult:
	var requested_id := String(definition.get("monster_id", ""))
	var requested_map_instance_id := String(definition.get("map_instance_id", ""))
	var requested_position: Variant = definition.get("position", Vector2.INF)
	var requested_health := int(definition.get("max_health", 0))
	var requested_respawn_seconds := float(definition.get("respawn_seconds", -1.0))
	if requested_id.is_empty() or requested_map_instance_id.is_empty() or not requested_position is Vector2:
		return DomainResult.failure(&"combat.invalid_monster_definition", "monster, map identity and position are required")
	if not requested_position.is_finite() or requested_health <= 0:
		return DomainResult.failure(&"combat.invalid_monster_definition", "monster position or health is invalid")
	if simulation_hz <= 0 or requested_respawn_seconds < 0.0:
		return DomainResult.failure(&"combat.invalid_monster_definition", "monster respawn timing is invalid")
	monster_id = requested_id
	map_instance_id = requested_map_instance_id
	position = requested_position
	max_health = requested_health
	health = max_health
	respawn_delay_ticks = roundi(requested_respawn_seconds * float(simulation_hz))
	respawn_at_tick = -1
	death_generation = 0
	last_killer_id = ""
	return DomainResult.ok(self)


## Applies [param amount] from [param attacker_id] at [param current_tick].
## [param amount] Server-calculated non-negative damage.
## [param attacker_id] Authenticated authoritative entity receiving kill attribution.
## [param current_tick] Fixed simulation tick used to schedule respawn.
## Returns damage/death facts, or rejects attacks against an already-dead generation.
## Design: Only the alive-to-dead edge increments generation and schedules one respawn.
func apply_damage(amount: int, attacker_id: String, current_tick: int) -> DomainResult:
	if health <= 0:
		return DomainResult.failure(&"combat.target_already_dead", "monster is already dead")
	if amount < 0 or attacker_id.is_empty() or current_tick < 0:
		return DomainResult.failure(&"combat.invalid_damage", "damage attribution is invalid")
	var applied := mini(amount, health)
	health -= applied
	var died := health == 0
	if died:
		death_generation += 1
		last_killer_id = attacker_id
		respawn_at_tick = current_tick + respawn_delay_ticks
	return DomainResult.ok({
		"applied_damage": applied,
		"health": health,
		"died": died,
		"death_generation": death_generation,
		"respawn_at_tick": respawn_at_tick,
	})


## Advances this lifecycle to [param current_tick] and performs a due respawn once.
## [param current_tick] Monotonic authoritative tick.
## Returns whether a respawn occurred and the current generation/health.
func advance_to_tick(current_tick: int) -> DomainResult:
	if current_tick < 0:
		return DomainResult.failure(&"combat.invalid_tick", "tick cannot be negative")
	var respawned := false
	if health == 0 and respawn_at_tick >= 0 and current_tick >= respawn_at_tick:
		health = max_health
		respawn_at_tick = -1
		last_killer_id = ""
		respawned = true
	return DomainResult.ok({
		"respawned": respawned,
		"death_generation": death_generation,
		"health": health,
	})


## Reports whether the current monster generation is alive.
## Returns true while combat health remains above zero.
func is_alive() -> bool:
	return health > 0


## Serializes lifecycle state for server module inspection.
## Returns a dictionary containing health, generation and respawn deadline.
func to_dictionary() -> Dictionary:
	return {
		"monster_id": monster_id,
		"map_instance_id": map_instance_id,
		"position": position,
		"max_health": max_health,
		"health": health,
		"respawn_delay_ticks": respawn_delay_ticks,
		"respawn_at_tick": respawn_at_tick,
		"death_generation": death_generation,
		"last_killer_id": last_killer_id,
	}
