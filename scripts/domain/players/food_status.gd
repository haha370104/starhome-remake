class_name FoodStatus
extends RefCounted

var physical := 100
var active: Array[FoodEffect] = []
var cooldowns: Dictionary = {}


## 还原体力及按效果类型保存的限时状态，旧存档默认满体力且无增益。
## [param state] 已校验的存档或网络状态。
func _init(state: Dictionary = {}) -> void:
	physical = int(state.get("physical", 100))
	cooldowns = state.get("cooldowns", {}).duplicate(true)
	for row: Dictionary in state.get("active", []):
		active.append(FoodEffect.new(row))


## 在存档及网络入口拒绝非法效果、时间或体力值。
## [param state] 待解析的原始状态。
## 返回是否符合食品状态契约。
static func valid_state(state: Variant) -> bool:
	if not state is Dictionary or not state.get("active", []) is Array or not state.get("cooldowns", {}) is Dictionary:
		return false
	if not state.get("physical", 100) is float and not state.get("physical", 100) is int:
		return false
	if not is_finite(float(state.get("physical", 100))) or float(state.get("physical", 100)) != floorf(float(state.get("physical", 100))):
		return false
	if int(state.get("physical", 100)) < 0 or int(state.get("physical", 100)) > 100:
		return false
	var seen: Array[int] = []
	for row: Variant in state.get("active", []):
		if not row is Dictionary:
			return false
		for key: String in ["kind", "amount", "duration", "cooldown", "expires_at", "last_tick"]:
			if not row.get(key) is int and not row.get(key) is float:
				return false
			if not is_finite(float(row[key])) or float(row[key]) < 0 or float(row[key]) != floorf(float(row[key])):
				return false
		var kind := int(row.kind)
		if kind < 1 or kind > 18 or kind in seen:
			return false
		seen.append(kind)
	for key: Variant in state.get("cooldowns", {}):
		if not String(key).is_valid_int() or int(key) < 1 or int(key) > 19:
			return false
		var value: Variant = state.cooldowns[key]
		if not value is int and not value is float:
			return false
		if not is_finite(float(value)) or float(value) < 0:
			return false
	return true


## 检查同类效果冷却，任何一项失败时整份食品都不能消耗。
## [param item] 待使用食品。
## [param now] 权威秒级时钟。
## 返回可使用或剩余冷却提示。
func can_eat(item: ConsumableItem, now: int) -> DomainResult:
	for effect: FoodEffect in item.effects:
		var remaining := int(cooldowns.get(str(effect.kind), 0)) - now
		if remaining > 0:
			return DomainResult.failure(&"items.food_cooldown", "同类食品效果还需冷却%d秒" % remaining)
	return DomainResult.ok()


## 恢复体力并用新效果替换相同类型，不同类型可共存。
## [param item] 已通过数量和冷却校验的食品。
## [param now] 权威使用时刻。
## 返回应立即恢复的战车生命值。
func eat(item: ConsumableItem, now: int) -> int:
	physical = mini(100, physical + item.physical)
	var vehicle_heal := 0
	for rule: FoodEffect in item.effects:
		cooldowns[str(rule.kind)] = now + rule.cooldown
		if rule.kind == 19:
			vehicle_heal += rule.amount
			continue
		active = active.filter(func(previous: FoodEffect) -> bool: return previous.kind != rule.kind)
		var effect := FoodEffect.new(rule.to_dictionary())
		effect.expires_at = now + rule.duration
		effect.last_tick = now
		active.append(effect)
	return vehicle_heal


## 查询尚未到期的属性加成，过期项即使尚未清理也绝不生效。
## [param kind] 原版效果类型。
## [param now] 可注入的权威时刻，负值使用当前时间。
## 返回当前加成值。
func bonus(kind: int, now: int = -1) -> int:
	var clock := int(Time.get_unix_time_from_system()) if now < 0 else now
	for effect: FoodEffect in active:
		if effect.kind == kind and effect.expires_at > clock:
			return effect.amount
	return 0


## 将原版技能经验百分比转换为乘数。
## [param skill_id] 经验事件的技能。
## 返回不小于一的经验倍率。
func experience_multiplier(skill_id: String) -> float:
	var kind := FoodEffect.SKILLS.find(skill_id)
	return 1.0 + float(bonus(kind)) / 100.0 if kind > 0 else 1.0


## 结算在线经过的回血秒数并清理到期项，同一时刻重复调用不重复回血。
## [param now] 权威当前时间。
## 返回本轮应恢复的人物生命。
func advance(now: int) -> int:
	var healing := 0
	for effect: FoodEffect in active:
		if effect.kind == 18:
			healing += maxi(0, mini(now, effect.expires_at) - effect.last_tick) * effect.amount
			effect.last_tick = maxi(effect.last_tick, mini(now, effect.expires_at))
	active = active.filter(func(effect: FoodEffect) -> bool: return effect.expires_at > now)
	return healing


## 重连时跳过离线回血，限时效果仍使用真实到期时间。
## [param now] 登录时刻。
func resume(now: int) -> void:
	for effect: FoodEffect in active:
		effect.last_tick = now
	advance(now)


## 导出独立状态，供存档及同事务玩家投影使用。
## 返回体力、增益和冷却映射。
func to_dictionary() -> Dictionary:
	var rows: Array[Dictionary] = []
	for effect: FoodEffect in active:
		rows.append(effect.to_dictionary())
	return {"physical": physical, "active": rows, "cooldowns": cooldowns.duplicate(true)}
