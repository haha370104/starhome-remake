class_name VehicleMovement
extends RefCounted

const DomainResult = preload("res://scripts/core/domain_result.gd")


## 执行 `effective_propulsion` 对应的模块操作。
## [param driving_skill_level] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param engine_required_level] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param engine_current_propulsion] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
static func effective_propulsion(
	driving_skill_level: int,
	engine_required_level: int,
	engine_current_propulsion: int,
) -> DomainResult:
	if driving_skill_level < 0 or engine_required_level < 0 or engine_current_propulsion < 0:
		return DomainResult.failure(&"invalid_vehicle_stat", "Driving and engine values must be non-negative")
	if engine_required_level == 0:
		return DomainResult.ok(engine_current_propulsion)
	var usable_skill := mini(driving_skill_level, engine_required_level)
	return DomainResult.ok(
		int(floor(float(usable_skill * engine_current_propulsion) / float(engine_required_level)))
	)


## 执行 `total_weight` 对应的模块操作。
## [param component_weights] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
static func total_weight(component_weights: Array[int]) -> DomainResult:
	var weight := 0
	for component_weight: int in component_weights:
		if component_weight < 0:
			return DomainResult.failure(&"invalid_component_weight", "Component weight must be non-negative")
		weight += component_weight
	return DomainResult.ok(weight)


## 执行 `base_speed` 对应的模块操作。
## [param driving_skill_level] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param engine_required_level] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param engine_current_propulsion] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param component_weights] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param config] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
static func base_speed(
	driving_skill_level: int,
	engine_required_level: int,
	engine_current_propulsion: int,
	component_weights: Array[int],
	config: Dictionary,
) -> DomainResult:
	var multiplier: int = int(config.get("base_speed_multiplier", 0))
	var speed_cap: int = int(config.get("base_speed_cap", 0))
	if multiplier <= 0 or speed_cap <= 0:
		return DomainResult.failure(&"invalid_vehicle_config", "Vehicle speed multiplier and cap must be positive")
	var weight_result := total_weight(component_weights)
	if not weight_result.is_ok:
		return weight_result
	var weight: int = int(weight_result.value)
	var propulsion_result := effective_propulsion(
		driving_skill_level,
		engine_required_level,
		engine_current_propulsion,
	)
	if not propulsion_result.is_ok:
		return propulsion_result
	var propulsion: int = int(propulsion_result.value)
	if weight <= 0 or propulsion <= 0:
		return DomainResult.ok({"speed": 0, "effective_propulsion": propulsion, "total_weight": weight})
	var speed := mini(int(floor(float(propulsion * multiplier) / float(weight))), speed_cap)
	return DomainResult.ok({
		"speed": speed,
		"effective_propulsion": propulsion,
		"total_weight": weight,
	})
