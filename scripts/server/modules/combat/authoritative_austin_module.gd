class_name AuthoritativeAustinModule
extends RefCounted

var _activations: Dictionary[String, AustinDefenseActivation] = {}
var _random := RandomNumberGenerator.new()


## 建立独立随机序列，避免改变掉落和基础攻击随机流。
## [param seed_value] 权威初始化种子。
func reset(seed_value: int) -> void:
	_activations.clear()
	_random.seed = seed_value


## 对真正命中的直接攻击结算防御后减伤及存活回血，持续腐蚀不进入此入口。
## [param actor_id] 玩家身份。[param condition] 实际运行装配。[param state] 战车资源。
## [param damage] 防御前伤害。[param tick] 当前时钟。[param hz] 模拟频率。
## 返回应用伤害与实际触发反馈。
func resolve_hit(actor_id: String, condition: EquipmentConditionLoadout, state: VehicleCombatState, damage: int, tick: int, hz: int) -> DomainResult:
	if state.health <= 0 or state.preview_damage(damage) <= 0: return state.apply_damage(damage)
	if not _activations.has(actor_id): _activations[actor_id] = AustinDefenseActivation.new()
	var effects: Array[Dictionary] = []
	var mitigation := 0
	for item: VehicleEquipment in condition.austin_equipment():
		if item.austin_profile.effect != "mitigation": continue
		var value := _activations[actor_id].claim(item, tick, hz, _random.randf())
		if value > 0:
			mitigation += value
			effects.append({"kind": "mitigation", "amount": mini(state.preview_damage(damage), value), "source_instance_id": item.instance_id})
	var result := state.apply_damage(damage, false, mitigation)
	if not result.is_ok: return result
	if state.health > 0 and state.health < state.max_health:
		for item: VehicleEquipment in condition.austin_equipment():
			if item.austin_profile.effect != "healing": continue
			var amount := _activations[actor_id].claim(item, tick, hz, _random.randf())
			if amount > 0:
				var repaired := state.repair_health(amount)
				effects.append({"kind": "healing", "amount": int(repaired.value.repaired_health), "source_instance_id": item.instance_id})
	result.value.health = state.health
	result.value["austin_effects"] = effects
	return result


## 清理已离开来源，保留成长刷新和其他装备变化之前的冷却。
## [param actor_id] 玩家身份。[param condition] 当前有效装配；死亡、切图或退出为空。
func retain_sources(actor_id: String, condition: EquipmentConditionLoadout = null) -> void:
	if not _activations.has(actor_id): return
	var ids := PackedStringArray()
	if condition != null:
		for item: VehicleEquipment in condition.austin_equipment(): ids.append(item.instance_id)
	_activations[actor_id].retain(ids)
	if ids.is_empty(): _activations.erase(actor_id)
