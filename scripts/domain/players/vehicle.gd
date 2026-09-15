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
## 返回战斗和装备面板共同消费的属性字典。
## 设计：属性计算属于战车聚合；UI 与应用服务只投影结果，不重复理解装备字段。
func calculate_stats(
	character_self_repair_bonus: int = 0,
	character_external_repair_bonus: int = 0,
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
	return {
		"health": health,
		"max_health": max_health,
		"max_health_base": chassis_base_health,
		"max_health_bonus": maxi(0, max_health - chassis_base_health),
		"defense": defense,
		"defense_base": defense,
		"defense_bonus": 0,
		"armor_front": int(armor_by_location[5]),
		"armor_rear": int(armor_by_location[6]),
		"armor_left": int(armor_by_location[7]),
		"armor_right": int(armor_by_location[8]),
		"speed": propulsion + (loadout.attachment_bonus("speed") if propulsion > 0 else 0),
		"energy_cannon_attack": primary_attack + ((achievement_bonuses.energy_cannon_attack + loadout.attachment_bonus("energy_cannon_attack")) if primary_attack > 0 else 0),
		"energy_cannon_attack_base": primary_attack,
		"energy_cannon_attack_bonus": (achievement_bonuses.energy_cannon_attack + loadout.attachment_bonus("energy_cannon_attack")) if primary_attack > 0 else 0,
		"energy_cannon_range_bonus": achievement_bonuses.energy_cannon_range,
		"missile_attack": achievement_bonuses.missile_attack + loadout.attachment_bonus("missile_attack"),
		"rocket_attack": achievement_bonuses.rocket_attack + loadout.attachment_bonus("rocket_attack"),
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
	max_health = chassis.base_max_health + achievement_bonuses.max_health + loadout.attachment_bonus("max_health")
	reserve_energy_capacity = chassis.reserve_energy_capacity
	working_energy_capacity = chassis.working_energy_capacity
	output_power = chassis.output_power
	if preserve_resource_ratios:
		health = clampi(roundi(health_ratio * float(max_health)), 0, max_health)
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
