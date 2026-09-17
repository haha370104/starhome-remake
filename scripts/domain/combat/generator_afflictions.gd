class_name GeneratorAfflictions
extends RefCounted

class Active extends RefCounted:
	var source_actor := ""
	var source_instance := ""
	var profile: GeneratorRules.Profile
	var expires_tick := 0

class HeatPulse extends RefCounted:
	var source_actor := ""
	var source_instance := ""
	var damage := 0

var _active: Array[Active] = []
var _next_heat_tick := -1
var _interval_ticks := 20


## 施加或刷新来源装备的效果，重复命中不推迟已安排的高热结算。
## [param profile] 已验证的装置基础规则。
## [param actor_id] 权威攻击者。
## [param instance_id] 实际消耗弹药的发生器实例。
## [param tick] 命中时服务器时钟。
## [param simulation_hz] 服务器频率。
func apply(profile: GeneratorRules.Profile, actor_id: String, instance_id: String, tick: int, simulation_hz: int) -> void:
	_interval_ticks = maxi(1, simulation_hz)
	var found: Active
	for entry: Active in _active:
		if entry.source_actor == actor_id and entry.source_instance == instance_id: found = entry
	if found == null:
		found = Active.new()
		_active.append(found)
	found.source_actor = actor_id
	found.source_instance = instance_id
	found.profile = profile
	found.expires_tick = tick + maxi(1, ceili(profile.duration_seconds * _interval_ticks))
	if profile.heat_damage > 0 and _next_heat_tick < 0: _next_heat_tick = tick + _interval_ticks


## 按目标独立时钟结算每秒最强高热，边界最后一秒仍有效。
## [param tick] 当前权威时钟。
## 返回一份带击杀归属的伤害脉冲或null；多个发生器不会倍增同类持续伤害。
func advance(tick: int) -> HeatPulse:
	for index: int in range(_active.size() - 1, -1, -1):
		if _active[index].expires_tick < tick: _active.remove_at(index)
	var strongest: Active
	for entry: Active in _active:
		if entry.profile.heat_damage > 0 and (strongest == null or entry.profile.heat_damage > strongest.profile.heat_damage): strongest = entry
	if strongest == null:
		_next_heat_tick = -1
		return null
	if tick < _next_heat_tick: return null
	_next_heat_tick = tick + _interval_ticks
	var pulse := HeatPulse.new()
	pulse.source_actor = strongest.source_actor
	pulse.source_instance = strongest.source_instance
	pulse.damage = strongest.profile.heat_damage
	return pulse


## 对防御使用最强固定削减与最强百分比削减，始终不低于零。
## [param base] 怪物本身的防御。
## 返回临时效果后的防御，不改写基础数值。
func defense_after(base: int) -> int:
	var flat := 0
	var percentage := 0.0
	for entry: Active in _active:
		flat = maxi(flat, entry.profile.defense_flat_reduction)
		percentage = maxf(percentage, entry.profile.defense_percent_reduction)
	return maxi(0, roundi(maxi(0, base - flat) * (1.0 - percentage)))


## 磁化降低已确认的通用攻击，专属能量炮压制仅接受明确标注的武器类型。
## [param base] 原始攻击。
## [param channel] 来源确认的伤害类型；未知怪物保持空值。
## 返回不改写基础配置的攻击值。
func attack_after(base: int, channel: String = "") -> int:
	var percentage := 0.0
	for entry: Active in _active:
		percentage = maxf(percentage, entry.profile.attack_percent_reduction)
		if channel == "energy_cannon": percentage = maxf(percentage, entry.profile.energy_attack_percent_reduction)
	return maxi(0, roundi(base * (1.0 - percentage)))


## 来源换装只保留仍装备的发生器；死亡和切图传空列表清空该来源。
## [param actor_id] 离开或刷新装配的玩家。
## [param retained_instances] 该玩家仍然有效的发生器实例。
func remove_source(actor_id: String, retained_instances: PackedStringArray = []) -> void:
	for index: int in range(_active.size() - 1, -1, -1):
		var entry := _active[index]
		if entry.source_actor == actor_id and entry.source_instance not in retained_instances: _active.remove_at(index)
	if _active.is_empty(): _next_heat_tick = -1


## 死亡、重新配置或复活时彻底清除临时状态。
func clear() -> void:
	_active.clear()
	_next_heat_tick = -1


## 导出已生效的状态名称，不把尚未识别目标类型的能量炮压制显示为生效。
## 返回去重的名称列表，供怪物血条旁显示。
func labels() -> PackedStringArray:
	var result := PackedStringArray()
	for entry: Active in _active:
		if entry.profile.heat_damage > 0 and "高热" not in result: result.append("高热")
		if (entry.profile.defense_flat_reduction > 0 or entry.profile.defense_percent_reduction > 0) and "蚀甲" not in result: result.append("蚀甲")
		if entry.profile.attack_percent_reduction > 0 and "磁化" not in result: result.append("磁化")
	return result
