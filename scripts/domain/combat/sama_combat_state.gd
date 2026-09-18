class_name SamaCombatState
extends RefCounted

class Effect extends RefCounted:
	var kind: String
	var source_id: String
	var ends_at: int
	var damage: int

var _active: Dictionary[String, Effect] = {}


## 对一次已接受能量炮射击判定该部件能力，不在命中或追加伤害时重复掷骰。
## [param item] 当前健康装备。[param roll] 权威随机样本。[param tick] 当前刻。[param hz] 模拟频率。
## 返回本次新激活效果；没有触发或PVP专属效果时为空。
func activate(item: VehicleEquipment, roll: float, tick: int, hz: int) -> Effect:
	if item == null or item.sama_profile == null or item.durability <= 0 or tick < 0 or hz <= 0 \
		or not is_finite(roll) or roll < 0 or roll >= 1 or roll >= item.sama.chance(item.sama_rules): return null
	var kind := item.sama_profile.effect
	if kind not in ["piercing", "pulse", "fission"]: return null
	var effect := Effect.new()
	effect.kind = kind
	effect.source_id = item.instance_id
	effect.damage = item.sama.damage(kind, item.sama_rules)
	effect.ends_at = tick + item.sama.duration(item.sama_rules) * hz
	if kind != "pulse": _active[kind] = effect
	return effect


## 获取仍有效的同来源能力；准确到期即清理，后续装配不会延长旧效果。
## [param kind] 能力种类。[param source_id] 要求的来源，空串表示查询当前能力。[param tick] 当前刻。
## 返回仍生效的实例状态或空值。
func active(kind: String, source_id: String, tick: int) -> Effect:
	var effect: Effect = _active.get(kind)
	if effect != null and effect.ends_at <= tick:
		_active.erase(kind)
		return null
	return effect if effect != null and (source_id.is_empty() or effect.source_id == source_id) else null


## 清理卸下或损坏的来源，不重置仍穿戴部件的剩余时间。
## [param ids] 当前有效装备身份。
func retain(ids: PackedStringArray) -> void:
	for kind: String in _active.keys():
		if _active[kind].source_id not in ids: _active.erase(kind)


## 判定前方矩形，不根据车身运动方向旋转射击范围。
## [param point] 怪物脚点。[param origin] 发射脚点。[param direction] 归一化瞄准方向。[param width] 前向长度及总宽。
## 返回是否位于前方范围内，边界包含在内。
static func inside_pulse(point: Vector2, origin: Vector2, direction: Vector2, width: float) -> bool:
	var relative := point - origin
	var forward := relative.dot(direction)
	return forward >= 0 and forward <= width and absf(relative.cross(direction)) <= width * 0.5
