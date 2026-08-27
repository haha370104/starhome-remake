class_name VehicleCombatState
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")

var max_health := 0
var health := 0
var reserve_energy_capacity := 0.0
var reserve_energy := 0.0
var working_energy_capacity := 0.0
var working_energy := 0.0
var power_output := 0.0
var passive_power_load := 0.0
var available_power_output := 0.0
var power_overloaded := false


## Initializes mutable vehicle resources from an injected calculated [param assembly].
## [param assembly] Validated result produced by `VehicleAssemblyCalculator`.
## Returns this state on success or a validation failure without partial initialization.
## Design: Both energy pools start full, while output power remains a non-consumable load budget.
func configure(assembly: Dictionary) -> DomainResult:
	var requested_health := int(assembly.get("max_health", 0))
	var requested_reserve := float(assembly.get("reserve_energy_capacity", -1.0))
	var requested_working := float(assembly.get("working_energy_capacity", -1.0))
	var requested_output := float(assembly.get("power_output", -1.0))
	var requested_load := float(assembly.get("passive_power_load", -1.0))
	if requested_health <= 0 or requested_reserve < 0.0 or requested_working <= 0.0:
		return DomainResult.failure(&"combat.invalid_assembly", "vehicle resource capacities are invalid")
	if requested_output < 0.0 or requested_load < 0.0:
		return DomainResult.failure(&"combat.invalid_assembly", "vehicle power budget is invalid")
	max_health = requested_health
	health = max_health
	reserve_energy_capacity = requested_reserve
	reserve_energy = reserve_energy_capacity
	working_energy_capacity = requested_working
	working_energy = working_energy_capacity
	power_output = requested_output
	passive_power_load = requested_load
	available_power_output = maxf(0.0, power_output - passive_power_load)
	power_overloaded = passive_power_load > power_output
	return DomainResult.ok(self)


## Consumes [param amount] exclusively from the working-energy pool.
## [param amount] Server-defined ability cost to reserve before an attack is emitted.
## Returns remaining working energy, or a failure that leaves both energy pools unchanged.
func consume_working_energy(amount: float) -> DomainResult:
	if not is_finite(amount) or amount < 0.0:
		return DomainResult.failure(&"combat.invalid_energy_cost", "energy cost must be finite and non-negative")
	if working_energy + 0.000001 < amount:
		return DomainResult.failure(&"combat.insufficient_working_energy", "working energy is insufficient")
	working_energy -= amount
	return DomainResult.ok(working_energy)


## Restores working energy over [param elapsed_seconds] by draining reserve energy.
## [param elapsed_seconds] Fixed-step server simulation time.
## [param regen_factor] Reconstructed conversion per available output-power unit per second.
## Returns the exact restored amount without changing the output-power budget.
## Design: Output power controls the rate, reserve energy supplies the resource, and working energy receives it.
func regenerate_working_energy(elapsed_seconds: float, regen_factor: float = 1.0) -> DomainResult:
	if elapsed_seconds < 0.0 or regen_factor < 0.0:
		return DomainResult.failure(&"combat.invalid_regeneration", "regeneration inputs cannot be negative")
	if power_overloaded or elapsed_seconds == 0.0 or regen_factor == 0.0:
		return DomainResult.ok(0.0)
	var missing := working_energy_capacity - working_energy
	var restored := minf(
		missing,
		minf(reserve_energy, available_power_output * regen_factor * elapsed_seconds),
	)
	working_energy += restored
	reserve_energy -= restored
	return DomainResult.ok(restored)


## Applies authoritative [param amount] to vehicle combat health.
## [param amount] Non-negative damage after server-side combat calculation.
## Returns applied damage, remaining health and newly-destroyed state.
func apply_damage(amount: int) -> DomainResult:
	if amount < 0:
		return DomainResult.failure(&"combat.invalid_damage", "damage cannot be negative")
	var was_alive := health > 0
	var applied := mini(amount, health)
	health -= applied
	return DomainResult.ok({
		"applied_damage": applied,
		"health": health,
		"destroyed": was_alive and health == 0,
	})


## Reports whether the vehicle can supply [param activation_power] without consuming it.
## [param activation_power] Weapon activation load checked against currently available output power.
## Returns true when the assembly is not overloaded and the transient load fits the budget.
func supports_activation_power(activation_power: float) -> bool:
	return activation_power >= 0.0 \
		and not power_overloaded \
		and activation_power <= available_power_output + 0.000001


## Serializes the three independent energy/power concepts and combat health.
## Returns a dictionary suitable for server snapshots and deterministic assertions.
func to_dictionary() -> Dictionary:
	return {
		"max_health": max_health,
		"health": health,
		"reserve_energy_capacity": reserve_energy_capacity,
		"reserve_energy": reserve_energy,
		"working_energy_capacity": working_energy_capacity,
		"working_energy": working_energy,
		"power_output": power_output,
		"passive_power_load": passive_power_load,
		"available_power_output": available_power_output,
		"power_overloaded": power_overloaded,
	}
