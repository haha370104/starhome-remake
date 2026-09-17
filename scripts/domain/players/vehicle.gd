class_name PlayerVehicle
extends RefCounted

var vehicle_id: String
var definition_id: String
var loadout: VehicleLoadout
var max_health: int
var health: int
var reserve_energy_capacity: float
var reserve_energy: float
var working_energy_capacity: float
var working_energy: float
var output_power: float
var achievement_bonuses := AchievementBonuses.new()
var food_status := FoodStatus.new()
var clothing_bonuses := ClothingBonuses.new()


## 初始化玩家拥有的战车实体及其运行时资源。
## [param state] 存档中的战车身份、生命和能源状态。
func _init(state: Dictionary = {}) -> void:
	vehicle_id = String(state.get("vehicle_id", ""))
	definition_id = String(state.get("definition_id", ""))
	loadout = VehicleLoadout.new(int(state.get("loadout_revision", 0)))
	max_health = maxi(1, int(state.get("max_health", 1)))
	health = clampi(int(state.get("health", max_health)), 0, max_health)
	reserve_energy_capacity = maxf(0.0, float(state.get("reserve_energy_capacity", 0.0)))
	reserve_energy = clampf(float(state.get("reserve_energy", 0.0)), 0.0, reserve_energy_capacity)
	working_energy_capacity = maxf(0.0, float(state.get("working_energy_capacity", 0.0)))
	working_energy = clampf(float(state.get("working_energy", 0.0)), 0.0, working_energy_capacity)
	output_power = maxf(0.0, float(state.get("output_power", 0.0)))


## 汇总底盘、引擎、武器、装甲及维修器得到当前战车属性。
## [param character_self_repair_bonus] 人物已穿装备提供的额外自维修力。
## [param character_external_repair_bonus] 人物已穿装备提供的对外维修力。
## [param driving_level] 当前有效驾驶技能，影响实际移动速度。
## 返回战斗和装备面板共同消费的属性字典。
## 设计：属性计算属于战车聚合；UI 与应用服务只投影结果，不重复理解装备字段。
func calculate_stats(
	character_self_repair_bonus: int = 0,
	character_external_repair_bonus: int = 0,
	driving_level: int = 1000000,
) -> Dictionary:
	var total_weight := 0
	var propulsion := 0
	var primary_attack := 0
	var defense := 0
	var armor_by_location := {5: 0, 6: 0, 7: 0, 8: 0}
	var chassis_base_health := 0
	var self_repair_base := 0
	var self_repair_bonus := maxi(0, character_self_repair_bonus) + achievement_bonuses.self_repair
	var extra_repair := maxi(0, character_external_repair_bonus)
	var self_repair_energy_cost := 0.0
	var required_repair_skill_level := 0
	for equipment: VehicleEquipment in loadout.items():
		total_weight += equipment.weight
		if equipment is VehicleChassis:
			var chassis := equipment as VehicleChassis
			chassis_base_health += chassis.base_max_health
			self_repair_base += chassis.self_repair_power()
			self_repair_energy_cost += chassis.self_repair_energy_cost
			required_repair_skill_level = maxi(
				required_repair_skill_level, chassis.required_repair_skill_level
			)
		elif equipment is VehicleEngine:
			propulsion += (equipment as VehicleEngine).drive
		elif equipment is VehicleWeapon and equipment.equipment_location == 1:
			primary_attack += (equipment as VehicleWeapon).base_attack
		if equipment.durability > 0:
			self_repair_bonus += maxi(0, int(equipment.stat("self_repair_bonus", 0)))
			extra_repair += maxi(0, int(equipment.stat("external_repair_bonus", 0)))
		var armor_value := int(equipment.stat("armor", 0))
		defense += armor_value
		if armor_by_location.has(equipment.equipment_location):
			armor_by_location[equipment.equipment_location] += armor_value
	self_repair_bonus += roundi(clothing_bonuses.apply_value("self_repair", 0))
	var final_defense := maxi(0, roundi(clothing_bonuses.apply_value("defense", defense)) + food_status.bonus(17))
	var cannon_attack := enhanced_attack("energy_cannon_attack", primary_attack, achievement_bonuses.energy_cannon_attack, 13)
	return {
		"health": health,
		"max_health": max_health,
		"max_health_base": chassis_base_health,
		"max_health_bonus": maxi(0, max_health - chassis_base_health),
		"defense": final_defense,
		"defense_base": defense,
		"defense_bonus": final_defense - defense,
		"armor_front": int(armor_by_location[5]),
		"armor_rear": int(armor_by_location[6]),
		"armor_left": int(armor_by_location[7]),
		"armor_right": int(armor_by_location[8]),
		"speed": movement_speed(driving_level),
		"energy_cannon_attack": cannon_attack,
		"energy_cannon_attack_base": primary_attack,
		"energy_cannon_attack_bonus": cannon_attack - primary_attack,
		"energy_cannon_range_bonus": clothing_bonuses.apply_value("energy_cannon_range", achievement_bonuses.energy_cannon_range),
		"missile_attack": enhanced_attack("missile_attack", _secondary_attack("missile"), achievement_bonuses.missile_attack, 14),
		"rocket_attack": enhanced_attack("rocket_attack", _secondary_attack("rocket_launcher"), achievement_bonuses.rocket_attack, 15),
		"propulsion": propulsion,
		"output_power": output_power,
		"weight": total_weight,
		"self_repair_base": self_repair_base,
		"self_repair_bonus": self_repair_bonus,
		"self_repair_total": self_repair_base + self_repair_bonus,
		"self_repair_energy_cost": self_repair_energy_cost,
		"required_repair_skill_level": required_repair_skill_level,
		"extra_repair": extra_repair,
		"reserve_energy": reserve_energy,
		"reserve_energy_capacity": reserve_energy_capacity,
		"working_energy": working_energy,
		"working_energy_capacity": working_energy_capacity,
	}


## 由固定装配槽重新派生战车身份、生命和能源上限，并按比例保留当前资源。
## [param preserve_resource_ratios] 上限变化时是否保留生命、储备能量和工作能量百分比。
## 返回找到有效底盘并完成同步时为 true；未安装底盘时保持原状态并返回 false。
## 设计：loadout 是装配事实来源，definition_id 与各项容量只是可持久化的运行时派生状态。
func reconcile_loadout_state(preserve_resource_ratios := true) -> bool:
	var chassis := loadout.at(0) as VehicleChassis
	if chassis == null:
		return false
	var health_ratio := _resource_ratio(health, max_health)
	var reserve_ratio := _resource_ratio(reserve_energy, reserve_energy_capacity)
	var working_ratio := _resource_ratio(working_energy, working_energy_capacity)
	definition_id = chassis.definition_id
	max_health = maxi(1, roundi(clothing_bonuses.apply_value("max_health", chassis.base_max_health + achievement_bonuses.max_health + loadout.attachment_bonus("max_health"))) + food_status.bonus(16))
	reserve_energy_capacity = chassis.reserve_energy_capacity
	working_energy_capacity = chassis.working_energy_capacity
	output_power = chassis.output_power
	for equipment: VehicleEquipment in loadout.items():
		if equipment != chassis:
			reserve_energy_capacity += float(equipment.stat("reserve_energy_capacity", 0.0))
			working_energy_capacity += float(equipment.stat("working_energy_capacity", 0.0))
			output_power += float(equipment.stat("power_output", 0.0))
	working_energy_capacity = maxf(1.0, clothing_bonuses.apply_value("working_energy_capacity", working_energy_capacity))
	output_power = maxf(0.0, clothing_bonuses.apply_value("output_power", output_power))
	if preserve_resource_ratios:
		health = clampi(floori(health_ratio * float(max_health) + 0.000001), 0, max_health)
		reserve_energy = clampf(reserve_ratio * reserve_energy_capacity, 0.0, reserve_energy_capacity)
		working_energy = clampf(working_ratio * working_energy_capacity, 0.0, working_energy_capacity)
	else:
		health = clampi(health, 0, max_health)
		reserve_energy = clampf(reserve_energy, 0.0, reserve_energy_capacity)
		working_energy = clampf(working_energy, 0.0, working_energy_capacity)
	return true


## 计算当前资源相对旧上限的安全比例。
## [param current_value] 当前资源值。
## [param capacity] 旧资源上限。
## 返回 0 到 1 的资源比例；无有效上限时按满值处理。
func _resource_ratio(current_value: float, capacity: float) -> float:
	return clampf(current_value / capacity, 0.0, 1.0) if capacity > 0.0 else 1.0


## 查询当前副武器的基础攻击，不把未安装的武器计入装备面板。
## [param mode] 导弹或火箭的战斗模式。
## 返回匹配副武器的基础攻击；空槽或不同类型返回零。
func _secondary_attack(mode: String) -> int:
	var weapon := loadout.at(13) as VehicleWeapon
	return weapon.base_attack if weapon != null and weapon.combat_mode() == mode else 0


## 统一计算武器的强化伤害，未装配该武器时不凭空产生攻击。
## [param attribute] 伤害属性类型。
## [param base] 武器基础伤害。
## [param title_bonus] 成就称号的固定加成。
## [param food_kind] 临时食品效果标识。
## 返回非负最终伤害。
func enhanced_attack(attribute: String, base: int, title_bonus: int, food_kind: int) -> int:
	if base <= 0:
		return 0
	return maxi(0, roundi(clothing_bonuses.apply_value(attribute, base + title_bonus + loadout.attachment_bonus(attribute))) + food_status.bonus(food_kind))


## 计算实际移动速度，宝石加在重量与驾驶技能折算后，最终受速度上限限制。
## [param driving_level] 有效驾驶技能。
## [param multiplier] 推进力和重量到像素每秒的换算值。
## [param cap] 地图规则速度上限。
## 返回实际像素每秒；缺少引擎或推进力时仍为零。
func movement_speed(driving_level: int, multiplier: float = 1500.0, cap: float = 240.0) -> float:
	var total_weight := 0
	var effective := 0.0
	for item: VehicleEquipment in loadout.items():
		total_weight += item.weight
		if item is VehicleEngine:
			effective += (item as VehicleEngine).drive * (minf(1.0, float(driving_level) / item.required_skill_level) if item.required_skill_level > 0 else 1.0)
	if effective <= 0.0 or total_weight <= 0:
		return 0.0
	var base := minf(floorf(effective * multiplier / total_weight), cap) + loadout.attachment_bonus("speed")
	return clampf(clothing_bonuses.apply_value("movement_speed", base), 1.0, cap)
