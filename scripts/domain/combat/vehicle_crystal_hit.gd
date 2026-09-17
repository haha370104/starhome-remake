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
