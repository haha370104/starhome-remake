class_name VehicleEngine
extends VehicleEquipment

var drive: int
var working_energy_cost: float


## 初始化提供移动速度与持续能耗的引擎。
## [param definition] 引擎配置定义。
## [param state] 存档中的引擎实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	refresh_processed_stats()


## 将推进力加工结果同步到移动计算读取的引擎属性。
func refresh_processed_stats() -> void:
	drive = maxi(0, int(stat("drive", 0)))
	working_energy_cost = maxf(0.0, float(stat("working_energy_cost", 0.0)))
