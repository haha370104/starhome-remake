class_name AuthoritativeSamaModule
extends RefCounted

var _states: Dictionary[String, SamaCombatState] = {}
var _random := RandomNumberGenerator.new()


## 建立独立触发随机流，避免改变既有攻击及掉落序列。
## [param seed_value] 权威种子。
func reset(seed_value: int) -> void:
	_states.clear()
	_random.seed = seed_value


## 对已扣能量的能量炮射击判定能力并冻结本发弹体可使用的来源。
## [param actor_id] 玩家身份。[param condition] 实际装配。[param tick] 当前刻。[param hz] 频率。
## 返回激活事件参数、来源及本发核变伤害，不携带客户端输入结果。
func accepted_shot(actor_id: String, condition: EquipmentConditionLoadout, tick: int, hz: int) -> Dictionary:
	if condition.sama_equipment().is_empty():
		_states.erase(actor_id)
		return {}
	if not _states.has(actor_id): _states[actor_id] = SamaCombatState.new()
	retain_sources(actor_id, condition)
	if not _states.has(actor_id): return {}
	var state := _states[actor_id]
	var activations: Array[Dictionary] = []
	for item: VehicleEquipment in condition.sama_equipment():
		var effect := state.activate(item, _random.randf(), tick, hz)
		if effect != null:
			activations.append({"kind": effect.kind, "source_instance_id": effect.source_id, "damage": effect.damage,
				"ends_at": effect.ends_at, "pulse_range": item.sama_rules.pulse_range})
	var result := {"activations": activations}
	for kind: String in ["piercing", "fission"]:
		var effect := state.active(kind, "", tick)
		if effect != null:
			result[kind] = effect.source_id
			if kind == "fission": result["fission_damage"] = effect.damage
	return result


## 检查某发弹体冻结的来源当前是否仍健康且处于有效期。
## [param actor_id] 玩家。[param condition] 实际装配。[param shot] 发射时效果快照。[param kind] 能力。[param tick] 当前刻。
## 返回是否允许本次穿透或追加伤害。
func permits(actor_id: String, condition: EquipmentConditionLoadout, shot: Dictionary, kind: String, tick: int) -> bool:
	var id := String(shot.get(kind, ""))
	if id.is_empty() or not _states.has(actor_id): return false
	retain_sources(actor_id, condition)
	return _states.has(actor_id) and _states[actor_id].active(kind, id, tick) != null


## 仅保留当前装备来源，死亡、离图及退出时一次清空。
## [param actor_id] 玩家。[param condition] 现有装配；空值表示清理全部。
func retain_sources(actor_id: String, condition: EquipmentConditionLoadout = null) -> void:
	if not _states.has(actor_id): return
	var ids := PackedStringArray()
	if condition != null:
		for item: VehicleEquipment in condition.sama_equipment(): ids.append(item.instance_id)
	_states[actor_id].retain(ids)
	if ids.is_empty(): _states.erase(actor_id)


## 向客户端提供持续状态与权威剩余时间，客户端不自行掷骰。
## [param actor_id] 玩家。[param condition] 当前装备。[param tick] 当前刻。[param hz] 模拟频率。
## 返回两种限时能力的安全快照。
func snapshot(actor_id: String, condition: EquipmentConditionLoadout, tick: int, hz: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	retain_sources(actor_id, condition)
	if not _states.has(actor_id): return result
	for kind: String in ["piercing", "fission"]:
		var effect := _states[actor_id].active(kind, "", tick)
		if effect != null: result.append({"kind": kind, "source_instance_id": effect.source_id, "remaining_seconds": float(effect.ends_at - tick) / hz})
	return result
