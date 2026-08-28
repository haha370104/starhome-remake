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


## 汇总底盘、引擎、武器及装甲得到当前战车属性。
## 返回战斗和装备面板共同消费的属性字典。
## 设计：属性计算属于战车聚合；UI 与应用服务只投影结果，不重复理解装备字段。
func calculate_stats() -> Dictionary:
	var total_weight := 0
	var propulsion := 0
	var primary_attack := 0
	var defense := 0
	var armor_by_location := {5: 0, 6: 0, 7: 0, 8: 0}
	var chassis_base_health := 0
	for equipment: VehicleEquipment in loadout.items():
		total_weight += equipment.weight
		if equipment is VehicleChassis:
			var chassis := equipment as VehicleChassis
			chassis_base_health += chassis.base_max_health
		elif equipment is VehicleEngine:
			propulsion += (equipment as VehicleEngine).drive
		elif equipment is VehicleWeapon and equipment.equipment_location == 1:
			primary_attack += (equipment as VehicleWeapon).base_attack
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
		"speed": propulsion,
		"energy_cannon_attack": primary_attack,
		"energy_cannon_attack_base": primary_attack,
		"energy_cannon_attack_bonus": 0,
		"missile_attack": 0,
		"rocket_attack": 0,
		"propulsion": propulsion,
		"output_power": output_power,
		"weight": total_weight,
		"self_repair_base": 0,
		"self_repair_bonus": 0,
		"extra_repair": 0,
		"reserve_energy": reserve_energy,
		"reserve_energy_capacity": reserve_energy_capacity,
		"working_energy": working_energy,
		"working_energy_capacity": working_energy_capacity,
	}
