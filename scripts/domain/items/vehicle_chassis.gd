class_name VehicleChassis
extends VehicleEquipment

var base_max_health: int
var base_armor: int
var working_energy_capacity: float
var reserve_energy_capacity: float
var output_power: float
var base_self_repair_power: int
var self_repair_energy_cost: float
var required_repair_skill_level: int


## 初始化决定战车基础生命、装甲与能源容量的底盘。
## [param definition] 底盘配置定义。
## [param state] 存档中的底盘实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	refresh_processed_stats()


## 将实例加工增量同步到生命与输出功率等底盘属性。
func refresh_processed_stats() -> void:
	base_max_health = maxi(1, int(stat("max_health", 1)))
	base_armor = maxi(0, int(stat("armor", 0)))
	working_energy_capacity = maxf(0.0, float(stat("working_energy_capacity", 0.0)))
	reserve_energy_capacity = maxf(0.0, float(stat("reserve_energy_capacity", 0.0)))
	output_power = maxf(0.0, float(stat("output_power", 0.0)))
	base_self_repair_power = maxi(0, int(stat("repair_strength", 0)))
	self_repair_energy_cost = maxf(0.0, float(stat("repair_energy_cost", 0.0)))
	required_repair_skill_level = maxi(0, int(stat("repair_skill_level", 0)))


## 判断玩家维修技能是否达到当前底盘内置维修器的使用门槛。
## [param repair_skill_level] 玩家由权威存档读取的维修技能基础等级。
## 返回达到 `m_nRepairLevel` 对应门槛时为 true。
func can_activate_self_repair(repair_skill_level: int) -> bool:
	return repair_skill_level >= required_repair_skill_level


## 汇总底盘固有自维修力与已验证的额外自维修加成。
## [param additional_power] 装备、服装、称号等来源提供的额外自维修力。
## 返回单次权威维修周期应恢复的生命值。
## 设计：维修技能只负责使用门槛；在恢复倍率得到服务器证据前不参与数值计算。
func self_repair_power(additional_power: int = 0) -> int:
	return base_self_repair_power + maxi(0, additional_power)
