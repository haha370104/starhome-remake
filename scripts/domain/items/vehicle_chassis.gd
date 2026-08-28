class_name VehicleChassis
extends VehicleEquipment

var base_max_health: int
var base_armor: int
var working_energy_capacity: float
var reserve_energy_capacity: float
var output_power: float


## 初始化决定战车基础生命、装甲与能源容量的底盘。
## [param definition] 底盘配置定义。
## [param state] 存档中的底盘实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	base_max_health = maxi(1, int(stat("max_health", 1)))
	base_armor = maxi(0, int(stat("armor", 0)))
	working_energy_capacity = maxf(0.0, float(stat("working_energy_capacity", 0.0)))
	reserve_energy_capacity = maxf(0.0, float(stat("reserve_energy_capacity", 0.0)))
	output_power = maxf(0.0, float(stat("output_power", 0.0)))
