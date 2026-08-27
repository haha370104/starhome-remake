class_name SkillProgression
extends RefCounted

const DomainResult = preload("res://scripts/core/domain_result.gd")
const SkillState = preload("res://scripts/domain/skills/skill_state.gd")


## Retrieves the requested value from the managed state.
## [param skill_id] Stable identifier of the target value.
## [param current_level] Input value consumed by the operation.
## [param config] Configuration data that controls the operation.
## Returns A domain result containing either the computed value or a validation error.
## Design: Keeps deterministic game rules independent from scene and UI state.
static func get_need_points(skill_id: StringName, current_level: int, config: Dictionary) -> DomainResult:
	var validation := _validate_level_and_config(skill_id, current_level, config)
	if not validation.is_ok:
		return validation
	var maximum_formula_level: int = int(config["maximum_formula_level"])
	var formula_level := mini(current_level, maximum_formula_level)
	var coefficient_result := _coefficient_for(skill_id, formula_level, config)
	if not coefficient_result.is_ok:
		return coefficient_result
	var coefficient: int = int(coefficient_result.value)
	var next_level: int = formula_level + 1
	var need_points: int = int(floor(float(next_level * next_level * coefficient) / 100.0))
	if need_points <= 0:
		return DomainResult.failure(&"invalid_skill_threshold", "Skill threshold must be positive")
	return DomainResult.ok(need_points)


## Advances the managed state using the supplied update.
## [param state] Input value consumed by the operation.
## [param grant] Input value consumed by the operation.
## [param config] Configuration data that controls the operation.
## Returns A domain result containing either the computed value or a validation error.
## Design: Keeps deterministic game rules independent from scene and UI state.
static func apply_exp(state: SkillState, grant: float, config: Dictionary) -> DomainResult:
	if state == null:
		return DomainResult.failure(&"missing_skill_state", "Skill state is required")
	if not is_finite(grant) or grant < 0.0:
		return DomainResult.failure(&"invalid_exp_grant", "Experience grant must be finite and non-negative")
	if state.current_exp < 0 or not is_finite(state.fractional_exp) or state.fractional_exp < 0.0 or state.fractional_exp >= 1.0:
		return DomainResult.failure(&"invalid_skill_state", "Skill experience state is invalid")
	var maximum_level: int = int(config.get("maximum_level", -1))
	if maximum_level < 0:
		return DomainResult.failure(&"invalid_skill_config", "maximum_level must be non-negative")
	if state.level >= maximum_level:
		return DomainResult.failure(&"skill_maximum_level", "Skill is already at maximum level")
	var threshold_result := get_need_points(state.skill_id, state.level, config)
	if not threshold_result.is_ok:
		return threshold_result
	var threshold: int = int(threshold_result.value)
	if state.current_exp >= threshold:
		return DomainResult.failure(&"invalid_skill_state", "Current experience must be below the level threshold")

	var accumulated := float(state.current_exp) + state.fractional_exp + grant
	var upgraded := accumulated >= float(threshold)
	var discarded_exp := 0.0
	if upgraded:
		discarded_exp = accumulated - float(threshold)
		state.level += 1
		state.current_exp = 0
		state.fractional_exp = 0.0
	else:
		state.current_exp = floori(accumulated)
		state.fractional_exp = accumulated - float(state.current_exp)
	return DomainResult.ok({
		"upgraded": upgraded,
		"new_level": state.level,
		"current_exp": state.current_exp,
		"fractional_exp": state.fractional_exp,
		"threshold": threshold,
		"discarded_exp": discarded_exp,
	})


## Validates the supplied state against the domain invariants.
## [param skill_id] Stable identifier of the target value.
## [param current_level] Input value consumed by the operation.
## [param config] Configuration data that controls the operation.
## Returns A domain result containing either the computed value or a validation error.
## Design: Keeps deterministic game rules independent from scene and UI state.
static func _validate_level_and_config(
	skill_id: StringName,
	current_level: int,
	config: Dictionary,
) -> DomainResult:
	if current_level < 0:
		return DomainResult.failure(&"invalid_skill_level", "Skill level must be non-negative")
	if not config.has("maximum_formula_level") or int(config["maximum_formula_level"]) < 0:
		return DomainResult.failure(&"invalid_skill_config", "maximum_formula_level must be non-negative")
	var coefficient_bands: Variant = config.get("coefficient_bands")
	if not coefficient_bands is Dictionary or not coefficient_bands.has(String(skill_id)):
		return DomainResult.failure(&"unknown_skill", "Unknown skill: %s" % String(skill_id))
	return DomainResult.ok()


## Performs the `coefficient_for` operation.
## [param skill_id] Stable identifier of the target value.
## [param level] Sequence, tick, or index value used by the operation.
## [param config] Configuration data that controls the operation.
## Returns A domain result containing either the computed value or a validation error.
## Design: Keeps deterministic game rules independent from scene and UI state.
static func _coefficient_for(skill_id: StringName, level: int, config: Dictionary) -> DomainResult:
	var coefficient_bands: Dictionary = config["coefficient_bands"]
	var bands: Variant = coefficient_bands[String(skill_id)]
	if not bands is Array or bands.is_empty():
		return DomainResult.failure(&"invalid_skill_config", "Skill coefficient bands must be a non-empty array")
	var coefficient := -1
	var previous_from_level := -1
	for raw_band: Variant in bands:
		if not raw_band is Dictionary or not raw_band.has("from_level") or not raw_band.has("coefficient"):
			return DomainResult.failure(&"invalid_skill_config", "Malformed coefficient band")
		var from_level: int = int(raw_band["from_level"])
		var band_coefficient: int = int(raw_band["coefficient"])
		if from_level <= previous_from_level or band_coefficient <= 0:
			return DomainResult.failure(&"invalid_skill_config", "Coefficient bands must be ordered and positive")
		previous_from_level = from_level
		if level >= from_level:
			coefficient = band_coefficient
	if coefficient <= 0:
		return DomainResult.failure(&"invalid_skill_config", "No coefficient band covers level %d" % level)
	return DomainResult.ok(coefficient)
