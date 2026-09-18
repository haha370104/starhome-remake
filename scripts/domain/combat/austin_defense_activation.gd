class_name AustinDefenseActivation
extends RefCounted

var _ready_ticks: Dictionary[String, int] = {}


## 对一件具有PVE受击能力的装备独立判定触发并占用冷却。
## [param item] 当前有效装备。[param tick] 权威时钟。[param hz] 模拟频率。[param roll] 服务端随机值。
## 返回触发的固定减伤或恢复量，未触发为零。
func claim(item: VehicleEquipment, tick: int, hz: int, roll: float) -> int:
	if item == null or item.austin_profile == null or item.austin_rules == null or item.durability <= 0 \
		or item.austin_profile.effect not in ["mitigation", "healing"] or tick < 0 or hz <= 0 \
		or not is_finite(roll) or roll < 0 or roll >= item.austin_rules.trigger_chance or roll >= 1 \
		or tick < _ready_ticks.get(item.instance_id, 0): return 0
	_ready_ticks[item.instance_id] = tick + item.austin_rules.cooldown_seconds * hz
	return item.austin_rules.mitigation[item.austin_glens.additional] if item.austin_profile.effect == "mitigation" else item.austin_rules.healing[item.austin_glens.additional]


## 刷新装配时保留相同来源冷却，仅清理离开或失效实例。
## [param ids] 当前有效的装备身份；死亡或离开时为空。
func retain(ids: PackedStringArray) -> void:
	for id: String in _ready_ticks.keys():
		if id not in ids: _ready_ticks.erase(id)
