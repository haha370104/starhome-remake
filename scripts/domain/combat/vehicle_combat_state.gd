class_name VehicleCombatState
extends RefCounted


var food_defense := 0
var defense := 0
var corrosion_reduction := 0.0
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


## 执行 `configure` 对应的模块操作。
## [param assembly] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
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
	food_defense = maxi(0, int(assembly.get("food_defense", 0)))
	defense = maxi(0, int(assembly.get("defense", 0)))
	corrosion_reduction = clampf(float(assembly.get("corrosion_reduction", 0.0)), 0.0, 0.3)
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


## 执行 `consume_working_energy` 对应的模块操作。
## [param amount] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func consume_working_energy(amount: float) -> DomainResult:
	if not is_finite(amount) or amount < 0.0:
		return DomainResult.failure(&"combat.invalid_energy_cost", "energy cost must be finite and non-negative")
	if working_energy + 0.000001 < amount:
		return DomainResult.failure(&"combat.insufficient_working_energy", "working energy is insufficient")
	working_energy -= amount
	return DomainResult.ok(working_energy)


## 执行 `regenerate_working_energy` 对应的模块操作。
## [param elapsed_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param regen_factor] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
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


## 执行 `apply_damage` 对应的模块操作。
## [param amount] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## [param corrosion_damage] 是否为地面或附着腐蚀的持续伤害。
## [param fixed_reduction] 防御结算后的额外固定减伤，由权威装备触发提供。
func apply_damage(amount: int, corrosion_damage := false, fixed_reduction := 0) -> DomainResult:
	if amount < 0 or fixed_reduction < 0:
		return DomainResult.failure(&"combat.invalid_damage", "damage cannot be negative")
	var was_alive := health > 0
	var mitigated := maxi(0, preview_damage(amount, corrosion_damage) - fixed_reduction)
	var applied := mini(mitigated, health)
	health -= applied
	return DomainResult.ok({
		"applied_damage": applied,
		"health": health,
		"destroyed": was_alive and health == 0,
	})


## 计算固定装备减伤之前的实际伤害，供同一次受击预检与结算共用。
## [param amount] 防御前伤害。[param corrosion_damage] 是否为腐蚀持续伤害。
## 返回尚未扣血的非负伤害。
func preview_damage(amount: int, corrosion_damage := false) -> int:
	var mitigated := CombatDefense.mitigate(maxi(0, amount - food_defense), defense)
	if corrosion_damage:
		mitigated = maxi(1, roundi(mitigated * (1.0 - corrosion_reduction))) if mitigated > 0 else 0
	return mitigated


## 在不超过最大生命的前提下恢复战车生命。
## [param amount] 本次权威维修请求恢复的非负生命值。
## 返回实际恢复量与维修后的生命；战车已毁或参数非法时返回领域错误。
## 设计：治疗截断规则属于可复用战车领域状态，服务器模块只负责周期与资源编排。
func repair_health(amount: int) -> DomainResult:
	if amount < 0:
		return DomainResult.failure(&"combat.invalid_repair", "repair amount cannot be negative")
	if health <= 0:
		return DomainResult.failure(&"combat.vehicle_destroyed", "destroyed vehicle cannot self-repair")
	var repaired := mini(amount, max_health - health)
	health += repaired
	return DomainResult.ok({
		"repaired_health": repaired,
		"health": health,
		"full_health": health >= max_health,
	})


## 执行 `supports_activation_power` 对应的模块操作。
## [param activation_power] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func supports_activation_power(activation_power: float) -> bool:
	return activation_power >= 0.0 \
		and not power_overloaded \
		and activation_power <= available_power_output + 0.000001


## 序列化或保存 `to_dictionary` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
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
