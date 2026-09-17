class_name GeneratorActivation
extends RefCounted

var _ready_ticks: Dictionary[String, int] = {}


## 在一次权威有效命中后独立判定指定发生器，不足弹药不影响已经发出的主炮。
## [param equipment] 当前模拟装配中的真实发生器实例。
## [param state] 同一战车的工作能量状态。
## [param tick] 命中时服务器时钟。
## [param simulation_hz] 服务器频率。
## [param roll] 服务器随机源给出的0到1之间数值，不接受客户端提交。
## 返回是否成功扣料并触发；失败不扣弹、不扣能量也不重置冷却。
func try_activate(equipment: VehicleEquipment, state: VehicleCombatState, tick: int, simulation_hz: int, roll: float) -> bool:
	if equipment == null or equipment.generator_profile == null or state == null or state.health <= 0 or equipment.durability <= 0:
		return false
	var profile := equipment.generator_profile
	if not profile.has_pve_effect(): return false
	if tick < 0 or simulation_hz <= 0 or not is_finite(roll) or roll < 0 or roll >= 1 or profile.chance <= 0 or roll >= profile.chance:
		return false
	if tick < _ready_ticks.get(equipment.instance_id, 0) or equipment.magazine.remaining <= 0:
		return false
	if not state.consume_working_energy(profile.working_energy_cost).is_ok: return false
	equipment.magazine.consume()
	_ready_ticks[equipment.instance_id] = tick + ceili(profile.cooldown_seconds * simulation_hz)
	return true


## 装配刷新只移除已离开实例，保留相同发生器的冷却，避免食品和保存刷新重置时序。
## [param instance_ids] 仍然有效的发生器身份。
func retain(instance_ids: PackedStringArray) -> void:
	for id: String in _ready_ticks.keys():
		if id not in instance_ids: _ready_ticks.erase(id)
