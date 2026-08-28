class_name VehicleAssemblyCalculator
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")


## 执行 `calculate` 对应的模块操作。
## [param chassis] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param components] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param driving_skill_level] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param movement_config] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
static func calculate(
	chassis: Dictionary,
	components: Array[Dictionary],
	driving_skill_level: int,
	movement_config: Dictionary,
) -> DomainResult:
	if driving_skill_level < 0:
		return DomainResult.failure(&"combat.invalid_driving_skill", "driving skill cannot be negative")
	var chassis_result := _validate_stat_definition(chassis, "chassis")
	if not chassis_result.is_ok:
		return chassis_result
	var total_weight := int(chassis.get("weight", 0))
	var max_health := int(chassis.get("max_health", 0))
	var reserve_capacity := float(chassis.get("reserve_energy_capacity", 0.0))
	var working_capacity := float(chassis.get("working_energy_capacity", 0.0))
	var power_output := float(chassis.get("power_output", 0.0))
	var passive_power_load := float(chassis.get("continuous_power_draw", 0.0))
	var effective_propulsion := 0.0
	for component: Dictionary in components:
		var component_result := _validate_stat_definition(component, "component")
		if not component_result.is_ok:
			return component_result
		total_weight += int(component.get("weight", 0))
		reserve_capacity += float(component.get("reserve_energy_capacity", 0.0))
		working_capacity += float(component.get("working_energy_capacity", 0.0))
		power_output += float(component.get("power_output", 0.0))
		passive_power_load += float(component.get("continuous_power_draw", 0.0))
		var propulsion := float(component.get("propulsion", 0.0))
		var required_level := int(component.get("required_driving_level", 0))
		if required_level <= 0:
			effective_propulsion += propulsion
		else:
			effective_propulsion += propulsion * minf(
				1.0, float(driving_skill_level) / float(required_level)
			)
	var speed_multiplier := float(movement_config.get("base_speed_multiplier", 0.0))
	var speed_cap := float(movement_config.get("base_speed_cap", 0.0))
	if speed_multiplier <= 0.0 or speed_cap <= 0.0:
		return DomainResult.failure(&"combat.invalid_movement_config", "speed multiplier and cap must be positive")
	if total_weight <= 0 or max_health <= 0:
		return DomainResult.failure(&"combat.invalid_vehicle_definition", "weight and chassis health must be positive")
	if reserve_capacity < 0.0 or working_capacity <= 0.0 or power_output < 0.0:
		return DomainResult.failure(&"combat.invalid_vehicle_definition", "vehicle capacities are invalid")
	var movement_speed := 0.0
	if effective_propulsion > 0.0:
		movement_speed = minf(
			floorf(effective_propulsion * speed_multiplier / float(total_weight)), speed_cap
		)
	var available_power_output := maxf(0.0, power_output - passive_power_load)
	return DomainResult.ok({
		"total_weight": total_weight,
		"effective_propulsion": effective_propulsion,
		"movement_speed": movement_speed,
		"max_health": max_health,
		"reserve_energy_capacity": reserve_capacity,
		"working_energy_capacity": working_capacity,
		"power_output": power_output,
		"passive_power_load": passive_power_load,
		"available_power_output": available_power_output,
		"power_overloaded": passive_power_load > power_output,
	})


## 执行 `validate_stat_definition` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param context] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func _validate_stat_definition(definition: Dictionary, context: String) -> DomainResult:
	for field_name: String in [
		"weight", "max_health", "max_durability", "reserve_energy_capacity", "working_energy_capacity",
		"power_output", "continuous_power_draw", "propulsion", "required_driving_level",
	]:
		var value: Variant = definition.get(field_name, 0)
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return DomainResult.failure(
				&"combat.invalid_vehicle_definition", "%s.%s must be numeric" % [context, field_name]
			)
		var numeric := float(value)
		if not is_finite(numeric) or numeric < 0.0:
			return DomainResult.failure(
				&"combat.invalid_vehicle_definition", "%s.%s cannot be negative" % [context, field_name]
			)
	return DomainResult.ok()
