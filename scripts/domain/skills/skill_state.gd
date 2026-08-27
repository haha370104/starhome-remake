class_name SkillState
extends RefCounted

var skill_id: StringName
var level: int
var current_exp: int
var fractional_exp: float


## Initializes a new instance with its required state.
## [param initial_skill_id] Stable identifier of the target value.
## [param initial_level] Input value consumed by the operation.
## [param initial_current_exp] Input value consumed by the operation.
## [param initial_fractional_exp] Input value consumed by the operation.
## Design: Keeps deterministic game rules independent from scene and UI state.
func _init(
	initial_skill_id: StringName,
	initial_level: int = 0,
	initial_current_exp: int = 0,
	initial_fractional_exp: float = 0.0,
) -> void:
	skill_id = initial_skill_id
	level = initial_level
	current_exp = initial_current_exp
	fractional_exp = initial_fractional_exp


## Serializes the current state into a transport-safe dictionary.
## Returns Structured result data produced by the operation.
## Design: Keeps deterministic game rules independent from scene and UI state.
func to_dictionary() -> Dictionary:
	return {
		"skill_id": String(skill_id),
		"level": level,
		"current_exp": current_exp,
		"fractional_exp": fractional_exp,
	}
