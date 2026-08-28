class_name SkillState
extends RefCounted

var skill_id: StringName
var level: int
var current_exp: int
var fractional_exp: float


## 使用调用方参数初始化当前实例。
## [param initial_skill_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param initial_level] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param initial_current_exp] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param initial_fractional_exp] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
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


## 序列化或保存 `to_dictionary` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func to_dictionary() -> Dictionary:
	return {
		"skill_id": String(skill_id),
		"level": level,
		"current_exp": current_exp,
		"fractional_exp": fractional_exp,
	}
