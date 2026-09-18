class_name PlayerCentralController
extends RefCounted

var _grades: Dictionary[String, int] = {}
var evolved := false


## 恢复角色永久芯片状态；空旧档是六类全部未激活。
## [param raw] 存档或快照边界。
## 返回合法控制器或拒绝伪造等级、缺少前置的进化状态。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary or not raw.get("grades", {}) is Dictionary or not raw.get("evolved", false) is bool:
		return DomainResult.failure(&"central.state", "中枢角色状态无效")
	var controller := PlayerCentralController.new()
	for key: Variant in raw.get("grades", {}):
		if key not in CentralRules.CHIP_IDS or not CentralRules.integer(raw.grades[key], 0, 3):
			return DomainResult.failure(&"central.state", "中枢芯片等级无效")
	for id: String in CentralRules.CHIP_IDS:
		controller._grades[id] = int(raw.get("grades", {}).get(id, 0))
	controller.evolved = bool(raw.get("evolved", false))
	if controller.evolved and controller.core_grade() != 3:
		return DomainResult.failure(&"central.state", "进化中枢要求六类芯片均为3级")
	return DomainResult.ok(controller)


## 查询某类芯片的永久等级。
## [param chip_id] 稳定芯片标识。
## 返回零表示未激活。
func grade(chip_id: String) -> int:
	return _grades.get(chip_id, 0)


## 按免费版的六类最低等级计算核心等级。
## 返回0到3，不取平均以免部分低级芯片绕过条件。
func core_grade() -> int:
	var minimum := 3
	for id: String in CentralRules.CHIP_IDS: minimum = mini(minimum, grade(id))
	return minimum


## 应用一个已由目录确认的桥接模块，激活与升级不能互相替代。
## [param module] 对应芯片及模块目标等级。
## 返回升级结果；拒绝重复、降级和未激活时使用高级模块。
func use_module(module: CentralRules.Module) -> DomainResult:
	if module == null: return DomainResult.failure(&"central.module", "请选择桥接模块")
	var current := grade(module.chip_id)
	if module.target_grade == 1 and current != 0: return DomainResult.failure(&"central.activated", "该芯片已激活")
	if module.target_grade > 1 and current == 0: return DomainResult.failure(&"central.inactive", "请先激活对应芯片")
	if current >= module.target_grade: return DomainResult.failure(&"central.grade", "该模块无法提升当前芯片")
	_grades[module.chip_id] = module.target_grade
	return DomainResult.ok(module.target_grade)


## 将满三级核心永久进化为圣焱型。
## 返回成功或前置条件错误。
func evolve() -> DomainResult:
	if evolved: return DomainResult.failure(&"central.evolved", "中枢核心已经进化")
	if core_grade() != 3: return DomainResult.failure(&"central.evolution_required", "六类桥接芯片均须达到3级")
	evolved = true
	return DomainResult.ok()


## 判断芯片此刻是否有可控制的装备，进化后原版常驻属性不再受零件条件限制。
## [param id] 芯片类别。[param loadout] 当前装配。
## 返回当前能否贡献常驻属性。
func active(id: String, loadout: VehicleLoadout) -> bool:
	if grade(id) == 0: return false
	if evolved: return true
	for item: VehicleEquipment in loadout.items():
		if item.durability <= 0: continue
		match id:
			"tank":
				if item is VehicleChassis: return true
			"engine":
				if item is VehicleEngine: return true
			"gun":
				if item is VehicleWeapon and item.equipment_location == 1 and item.combat_mode() == "energy_cannon": return true
			"missile":
				if item is VehicleWeapon and item.equipment_location == 13 and item.combat_mode() == "missile": return true
			"armor":
				if item.equipment_location in [5, 6, 7, 8, 23]: return true
			"generator":
				if item.generator_profile != null and item.equipment_location in [14, 34]: return true
	return false


## 汇总角色芯片加成，四块护甲或两个发生器均只计算一次对应芯片。
## [param attribute] 战车属性。[param loadout] 当前装配。[param rules] 规则。
## 返回常驻固定加成，由战车统一应用倍率。
func bonus(attribute: String, loadout: VehicleLoadout, rules: CentralRules) -> int:
	if rules == null: return 0
	var total := int(rules.evolution_bonus.get(attribute, 0)) if evolved else 0
	for id: String in CentralRules.CHIP_IDS:
		if active(id, loadout): total += int(rules.chips[id].bonuses[grade(id) - 1].get(attribute, 0))
	return total


## 结算一次合法炮击的致命伤害，概率由权威战斗模块给出。
## [param current_health] 普通命中后尚存生命。[param ordinary_damage] 本次普通伤害。
## [param roll] 服务端独立随机值0到1。[param rules] 概率及复刻伤害上限。
## 返回额外固定伤害；不负责扣血或发送事件。
func fatal_damage(current_health: int, ordinary_damage: int, roll: float, rules: CentralRules) -> int:
	var gun_grade := grade("gun")
	if gun_grade == 0 or current_health <= 0 or ordinary_damage <= 0 or roll < 0 or roll >= 1: return 0
	if roll * 100.0 >= rules.fatal_chance_percent[gun_grade - 1]: return 0
	return mini(floori(current_health * rules.fatal_current_health_percent / 100.0), ordinary_damage * rules.fatal_damage_cap_multiplier)


## 导出永久事实，未保存派生加成或临时战斗状态。
## 返回独立字典。
func to_dictionary() -> Dictionary:
	var grades := {}
	for id: String in CentralRules.CHIP_IDS: grades[id] = grade(id)
	return {"grades": grades, "evolved": evolved}
