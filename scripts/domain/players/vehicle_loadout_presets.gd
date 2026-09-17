class_name VehicleLoadoutPresets
extends RefCounted

const COUNT := 4
const COOLDOWN_SECONDS := 30
var revision := 0
var ready_at := 0
var _sets: Array[Dictionary] = [{}, {}, {}, {}]


## 严格还原四套实际实例方案，旧存档缺省为空，拒绝重复槽位或重复装备。
## [param raw] 持久化或网络边界载荷。
## 返回独立的方案集合或格式错误。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary: return _invalid()
	var presets := VehicleLoadoutPresets.new()
	if raw.is_empty(): return DomainResult.ok(presets)
	if not valid_integer(raw.get("revision")) or not valid_integer(raw.get("ready_at")): return _invalid()
	var sets: Variant = raw.get("sets")
	if not sets is Array or sets.size() != COUNT: return _invalid()
	var normalized: Array[Dictionary] = []
	for value: Variant in sets:
		if not value is Dictionary: return _invalid()
		if value.is_empty():
			normalized.append({})
			continue
		if not value.get("name") is String or value.name.is_empty() or value.name.length() > 24: return _invalid()
		var slots: Variant = value.get("slots")
		if not slots is Array or slots.is_empty() or slots.size() > EquipmentSlotRegistry.LOCATION_DEFINITIONS.size(): return _invalid()
		var locations: Dictionary = {}
		var identities: Dictionary = {}
		var canonical_slots: Array[Dictionary] = []
		for slot: Variant in slots:
			if not slot is Dictionary or not valid_integer(slot.get("location")): return _invalid()
			var location := int(slot.location)
			if not EquipmentSlotRegistry.LOCATION_DEFINITIONS.has(location) or locations.has(location): return _invalid()
			for key: String in ["instance_id", "definition_id", "display_name"]:
				if not slot.get(key) is String or slot[key].is_empty() or slot[key].length() > 256: return _invalid()
			if identities.has(slot.instance_id): return _invalid()
			identities[slot.instance_id] = true
			locations[location] = true
			canonical_slots.append({"location": location, "instance_id": String(slot.instance_id),
				"definition_id": String(slot.definition_id), "display_name": String(slot.display_name)})
		if not locations.has(0): return _invalid()
		normalized.append({"name": String(value.name), "slots": canonical_slots})
	presets.revision = int(raw.revision)
	presets.ready_at = int(raw.ready_at)
	presets._sets.assign(normalized)
	return DomainResult.ok(presets)


## 仅接受JSON可精确表达的非负整数，不把小数、布尔或无穷值强转为版本。
## [param value] 边界数值。
## 返回是否可安全转换。
static func valid_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) >= 0 and float(value) <= 9007199254740991.0 and float(value) == floorf(float(value))


## 生成独立的四套方案与冷却记录，不保存装备副本或派生战斗数值。
## 返回持久化载荷。
func to_dictionary() -> Dictionary:
	return {"revision": revision, "ready_at": ready_at, "sets": _sets.duplicate(true)}


## 读取单套只读方案，用稳定槽位与实际实例定位装备。
## [param index] 0到3的方案序号。
## 返回方案副本，不存在时为空。
func at(index: int) -> Dictionary:
	return _sets[index].duplicate(true) if index >= 0 and index < COUNT else {}


## 从服务端当前装配保存方案，旧版本或无底盘时不覆盖已有方案。
## [param index] 目标方案。[param title] 用户标题。[param loadout] 当前真实装配。
## [param expected_revision] 方案版本。[param expected_loadout_revision] 用户查看的装配版本。
## 返回保存结果；仅推进方案版本，不移动任何物品。
func capture(index: int, title: String, loadout: VehicleLoadout, expected_revision: int, expected_loadout_revision: int) -> DomainResult:
	if expected_revision != revision: return _stale()
	if index < 0 or index >= COUNT or title.strip_edges().is_empty() or title.length() > 24: return _invalid()
	var checked := loadout.require_revision(expected_loadout_revision)
	if not checked.is_ok: return checked
	if not loadout.has_chassis(): return DomainResult.failure(&"equipment.chassis_required", "请先装配战车底盘")
	var slots: Array[Dictionary] = []
	for item: VehicleEquipment in loadout.items():
		slots.append({"location": item.equipment_location, "instance_id": item.instance_id,
			"definition_id": item.definition_id, "display_name": item.display_name})
	_sets[index] = {"name": title.strip_edges(), "slots": slots}
	revision += 1
	return DomainResult.ok()


## 原子应用具体实例方案；整体交换成功后才开始原版30秒冷却。
## [param player] 拥有背包与装配的玩家。[param index] 方案序号。[param now] 服务端时刻。
## [param expected_revision] 方案版本。[param inventory_revision] 背包版本。
## [param loadout_revision] 装配版本。[param in_field] 权威地图是否使用战车战斗。
## 返回应用结果，失败不移动物品、不改变资源或冷却。
func apply(player: Player, index: int, now: int, expected_revision: int, inventory_revision: int, loadout_revision: int, in_field: bool) -> DomainResult:
	if player == null or player.vehicle_presets != self or now < 0: return _invalid()
	if expected_revision != revision: return _stale()
	var selected := at(index)
	if selected.is_empty(): return DomainResult.failure(&"presets.empty", "此方案尚未保存")
	if now < ready_at: return DomainResult.failure(&"presets.cooldown", "换装冷却剩余%d秒" % (ready_at - now))
	if player.vehicle.health <= 0 or player.health <= 0: return DomainResult.failure(&"presets.destroyed", "被击毁时不能切换装备方案")
	var result := VehicleLoadoutExchange.apply(player, selected.slots, inventory_revision, loadout_revision, in_field)
	if not result.is_ok: return result
	ready_at = now + COOLDOWN_SECONDS
	revision += 1
	return DomainResult.ok()


## 构造格式拒绝，保持边界错误一致。
## 返回领域失败。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"presets.invalid", "装备方案格式或序号无效")


## 拒绝用户查看后已经被改写的方案。
## 返回版本失败。
static func _stale() -> DomainResult:
	return DomainResult.failure(&"presets.stale", "装备方案已更新，请重新选择")
