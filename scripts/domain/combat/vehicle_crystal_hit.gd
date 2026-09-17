class_name VehicleCrystalHit
extends RefCounted


## 在命中时判定普通暴击晶石，导弹和火箭不继承能量炮的暴击率。
## [param damage] 本次基础伤害。
## [param skill_id] 武器技能类型。
## [param chance] 全身晶石结算后的概率。
## [param multiplier] 版本化规则中的暴击倍率。
## [param roll] 服务端随机样本。
## 返回应用一次晶石暴击后的伤害。
static func resolve(damage: int, skill_id: String, chance: float, multiplier: float, roll: float) -> int:
	if skill_id != "energy_cannon" or not is_finite(chance) or not is_finite(multiplier) \
		or roll < 0 or roll >= clampf(chance, 0, 1):
		return damage
	return roundi(damage * clampf(multiplier, 1.0, 3.0))


## 分别判定晶石暴击与萤石/耀石双倍攻击，同时触发时只取较高倍率。
## [param damage] 未应用两种随机加成的伤害。
## [param weapon] 权威武器的技能、概率和晶石倍率。
## [param critical_roll] 晶石随机样本。
## [param double_roll] 额外属性随机样本。
## 返回一次结算的伤害；独立概率、不连乘是复刻组合规则。
static func resolve_extra(damage: int, weapon: Dictionary, critical_roll: float, double_roll: float) -> int:
	var skill := String(weapon.get("skill_id", ""))
	var critical := resolve(damage, skill, float(weapon.get("critical_chance", 0)), float(weapon.get("critical_multiplier", 1.5)), critical_roll)
	var double_hit := resolve(damage, skill, float(weapon.get("double_damage_chance", 0)), 2.0, double_roll)
	return maxi(critical, double_hit)
