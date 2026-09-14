class_name AchievementBonuses
extends RefCounted

const FIELDS := ["energy_cannon_attack", "energy_cannon_range", "rocket_attack", "missile_attack", "max_health", "self_repair"]
var energy_cannon_attack := 0
var energy_cannon_range := 0
var rocket_attack := 0
var missile_attack := 0
var max_health := 0
var self_repair := 0


## 从已校验称号配置创建固定加值，不修改装备基础属性。
## [param values] 当前唯一生效称号的增益配置。
func _init(values: Dictionary = {}) -> void:
	for field: String in FIELDS:
		set(field, maxi(0, int(values.get(field, 0))))


## 查询指定武器技能的称号攻击加值。
## [param skill_id] 能量炮、火箭炮或导弹技能标识。
## 返回该武器的攻击加值；非战斗技能为零。
func attack_for(skill_id: String) -> int:
	match skill_id:
		"energy_cannon": return energy_cannon_attack
		"rocket_launcher": return rocket_attack
		"missile": return missile_attack
	return 0


## 将增益应用到独立的权威武器定义，保持原始目录和已发射弹体不变。
## [param definition] 装配目录生成的基础武器协议。
## 返回叠加当前称号后的副本。
func apply_weapon(definition: Dictionary) -> Dictionary:
	var result := definition.duplicate(true)
	var skill_id := String(result.get("skill_id", ""))
	var attack := attack_for(skill_id)
	result["minimum_damage"] = int(result.get("minimum_damage", 0)) + attack
	result["maximum_damage"] = int(result.get("maximum_damage", 0)) + attack
	if skill_id == "energy_cannon":
		result["range"] = float(result.get("range", 0)) + energy_cannon_range
		result["upgrade_range_limit"] = float(definition.get("upgrade_range_limit", definition.get("range", 0))) + energy_cannon_range
	return result


## 将当前增益转换为只读展示数据。
## 返回各项固定加值的独立字典。
func to_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for field: String in FIELDS:
		result[field] = get(field)
	return result
