class_name CrystalSourceGrowth
extends RefCounted

class Slot extends RefCounted:
	var definition_id := ""
	var cracks := 0
	var bound := false

var quality := 0
var growth := 0
var slots: Array[Slot] = [Slot.new(), Slot.new(), Slot.new()]


## 恢复独立晶源体事实，三个默认空槽不依赖普通装备开孔状态。
## [param raw] 存档或快照边界字段。
## 返回有效实例或格式错误。
static func restore(raw: Variant) -> DomainResult:
	var value := CrystalSourceGrowth.new()
	if not raw is Dictionary: return _invalid()
	if raw.is_empty(): return DomainResult.ok(value)
	if raw.get("version") != 1 or not CrystalSourceRules.integer(raw.get("quality"), 0, 15) \
		or not CrystalSourceRules.integer(raw.get("growth"), 0, 15) \
		or not raw.get("slots") is Array or raw.slots.size() != 3: return _invalid()
	value.quality = int(raw.quality)
	value.growth = int(raw.growth)
	for index in 3:
		var row: Variant = raw.slots[index]
		if not row is Dictionary: return _invalid()
		if row.is_empty(): continue
		if not row.get("definition_id") is String or String(row.definition_id).is_empty() \
			or not CrystalSourceRules.integer(row.get("cracks"), 0, 3) or not row.get("bound") is bool: return _invalid()
		value.slots[index].definition_id = String(row.definition_id)
		value.slots[index].cracks = int(row.cracks)
		value.slots[index].bound = bool(row.bound)
	return DomainResult.ok(value)


## 校验此状态仅属于晶源体，且每种颜色至多一枚。
## [param profile] 装备规则，普通物品为空。[param rules] 权威核心目录。
## 返回资格与核心组合校验结果。
func validate_for(profile: CrystalSourceRules.Profile, rules: CrystalSourceRules) -> DomainResult:
	if profile == null and not to_dictionary().is_empty(): return _invalid()
	var colors := PackedStringArray()
	for slot: Slot in slots:
		if slot.definition_id.is_empty(): continue
		var core: CrystalSourceRules.Core = rules.cores.get(slot.definition_id)
		if core == null or core.color in colors: return _invalid()
		colors.append(core.color)
	return DomainResult.ok()


## 汇总部件基础、两条成长与三枚核心的同种属性。
## [param attribute] 战车统一属性。[param profile] 部件规则。[param rules] 核心规则。
## 返回固定加值；未匹配部件为零。
func bonus(attribute: String, profile: CrystalSourceRules.Profile, rules: CrystalSourceRules) -> int:
	if profile == null: return 0
	var result := 0
	if attribute == profile.attribute:
		result = profile.base + mini(quality, 10) * profile.quality_steps[0] + maxi(quality - 10, 0) * profile.quality_steps[1] \
			+ mini(growth, 10) * profile.growth_steps[0] + maxi(growth - 10, 0) * profile.growth_steps[1]
	for slot: Slot in slots:
		var core: CrystalSourceRules.Core = rules.cores.get(slot.definition_id)
		if core != null and core.attribute == attribute: result += core.bonus
	return result


## 在独立候选上镶嵌一枚指定核心，不支付库存。
## [param index] 零基孔位。[param core] 可用核心物品。[param rules] 核心目录。
## 返回镶嵌结果，失败不改变孔位。
func inlay(index: int, core: CrystalSourceCore, rules: CrystalSourceRules) -> DomainResult:
	if index < 0 or index >= 3 or not slots[index].definition_id.is_empty() or core == null or core.locked:
		return DomainResult.failure(&"crystal_source.slot", "请选择空晶源核槽与未锁定核心")
	for slot: Slot in slots:
		var installed: CrystalSourceRules.Core = rules.cores.get(slot.definition_id)
		if installed != null and installed.color == core.profile.color:
			return DomainResult.failure(&"crystal_source.duplicate_color", "每件晶源体同色核心最多一枚")
	slots[index].definition_id = core.definition_id
	slots[index].cracks = core.cracks
	slots[index].bound = core.bound
	return DomainResult.ok()


## 依据权威随机结果推进品质或成长，保护只抑制品质失败退级。
## [param channel] quality或growth。[param success] 随机结果。[param protected] 是否使用品质保护。[param rules] 规则。
## 返回本次变化；不承担库存支付。
func advance(channel: String, success: bool, protected: bool, rules: CrystalSourceRules) -> DomainResult:
	if channel not in ["quality", "growth"]: return _invalid()
	var before := quality if channel == "quality" else growth
	if before >= rules.maximum_level or (protected and (channel != "quality" or before < 3)):
		return DomainResult.failure(&"crystal_source.maximum", "已到成长上限，或本级无需品质保护")
	var after := before + 1 if success else before
	if channel == "quality":
		if not success and not protected: after = rules.quality_failure_levels[before]
		quality = after
	else:
		growth = after
	return DomainResult.ok({"before": before, "after": after, "success": success})


## 序列化最小成长事实，未成长且未镶嵌时使用旧档默认空对象。
## 返回深层独立字典。
func to_dictionary() -> Dictionary:
	var values: Array[Dictionary] = []
	var occupied := false
	for slot: Slot in slots:
		var row: Dictionary = {}
		if not slot.definition_id.is_empty():
			row = {"definition_id": slot.definition_id, "cracks": slot.cracks, "bound": slot.bound}
			occupied = true
		values.append(row)
	return {"version": 1, "quality": quality, "growth": growth, "slots": values} if occupied or quality > 0 or growth > 0 else {}


## 构造晶源体存档错误，避免把非法数据静默归零。
## 返回统一领域失败。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"crystal_source.state", "晶源体成长或核心状态无效")
