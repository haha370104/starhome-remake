class_name AustinGlensGrowth
extends RefCounted

class Slot extends RefCounted:
	var opened := false
	var rune_id := ""
	var bound := false

var color := 0
var stage := 0
var base := 0
var additional := 0
var blessed := false
var slots: Array[Slot] = [Slot.new(), Slot.new()]


## 恢复此系列独立的成长与固定符文事实；旧档缺字段时使用全新装备状态。
## [param raw] 存档边界。
## 返回实例或无效状态错误。
static func restore(raw: Variant) -> DomainResult:
	var value := AustinGlensGrowth.new()
	if not raw is Dictionary: return _invalid()
	if raw.is_empty(): return DomainResult.ok(value)
	if raw.get("version") != 1 or not raw.get("blessed") is bool or not raw.get("slots") is Array or raw.slots.size() != 2: return _invalid()
	for key: String in ["color", "stage", "base", "additional"]:
		if not AustinGlensRules.integer(raw.get(key), 0, 3 if key == "color" else 10): return _invalid()
		value.set(key, int(raw[key]))
	value.blessed = bool(raw.blessed)
	for index in 2:
		var row: Variant = raw.slots[index]
		if not row is Dictionary or not row.get("opened") is bool or not row.get("rune_id") is String or not row.get("bound") is bool: return _invalid()
		if (not row.opened and not row.rune_id.is_empty()) or (row.rune_id.is_empty() and row.bound): return _invalid()
		value.slots[index].opened = bool(row.opened)
		value.slots[index].rune_id = String(row.rune_id)
		value.slots[index].bound = bool(row.bound)
	return DomainResult.ok(value)


## 验证成长归属和每个固定符文的装备及左右位置。
## [param profile] 物品专属规则，非此系列时为空。[param rules] 符文目录。
## 返回合法性判定。
func validate_for(profile: AustinGlensRules.Profile, rules: AustinGlensRules) -> DomainResult:
	if profile == null and not to_dictionary().is_empty(): return _invalid()
	for index in 2:
		var slot := slots[index]
		if slot.rune_id.is_empty(): continue
		var rune: AustinGlensRules.Rune = rules.runes.get(slot.rune_id)
		if profile == null or rune == null or rune.location != profile.location or rune.slot != index: return _invalid()
	return DomainResult.ok()


## 汇总颜色、阶段、基础、祝福及符文固定加值；穿透仅保留原始数值供说明核对。
## [param attribute] 统一属性标识。[param rules] 只读规则。
## 返回单件未考虑耐久的常驻加值。
func bonus(attribute: String, rules: AustinGlensRules) -> int:
	var result := 0
	match attribute:
		"max_health": result = rules.color_health[color]
		"defense": result = rules.color_defense[color]
		"energy_cannon_attack": result = rules.stage_cannon[stage] + rules.stage_cannon[base]
		"missile_attack": result = rules.stage_missile[stage] + rules.stage_missile[base]
		"self_repair_bonus": result = rules.base_repair[base]
		"penetration": result = rules.color_penetration[color] + rules.stage_penetration[stage]
	if blessed: result += int(rules.blessing_bonuses.get(attribute, 0))
	for slot: Slot in slots:
		var rune: AustinGlensRules.Rune = rules.runes.get(slot.rune_id)
		if rune != null: result += int(rune.bonuses.get(attribute, 0))
	return result


## 在独立候选上执行确定成长并给出原版材料清单，失败不改变候选。
## [param operation] 成长或开孔镶嵌操作。[param profile] 目标部件。[param rules] 成本规则。
## [param slot_index] 开孔或镶入位置。[param rune_id] 实际符文定义。[param rune_bound] 实际符文绑定。
## 返回材料要求；聚合根完成支付后才能采用此候选。
func change(operation: String, profile: AustinGlensRules.Profile, rules: AustinGlensRules, slot_index := -1, rune_id := "", rune_bound := false) -> DomainResult:
	if profile == null or operation not in AustinGlensRules.OPERATIONS: return _invalid()
	var requirements: Array[Dictionary] = []
	var material := ""
	var amount := 0
	var space := 0
	match operation:
		"color":
			if color >= 3: return _maximum()
			material = "light_essence"
			amount = rules.color_costs[color]
			space = rules.color_space_costs[color]
			color += 1
		"stage", "base", "additional":
			var before := int(get(operation))
			if before >= 10: return _maximum()
			if operation == "additional" and profile.effect not in ["mitigation", "healing"]:
				return DomainResult.failure(&"austin.pvp_only", "此部件附加能力仅对其他玩家生效，本轮暂不开放升级")
			material = String({"stage": "primal_spirit", "base": "eternal_energy", "additional": "magic_core"}[operation])
			amount = rules.level_costs[before]
			space = rules.space_costs[before]
			set(operation, before + 1)
		"blessing":
			if blessed: return _maximum()
			material = "heritage_blessing"
			amount = rules.blessing_cost
			space = rules.blessing_space_cost
			blessed = true
		"unlock", "inlay":
			if slot_index < 0 or slot_index >= 2: return _invalid()
			var slot := slots[slot_index]
			material = "dispel_stone"
			if operation == "unlock":
				if slot.opened: return DomainResult.failure(&"austin.slot", "该符文槽已经开启")
				amount = rules.unlock_cost
				slot.opened = true
			else:
				var rune: AustinGlensRules.Rune = rules.runes.get(rune_id)
				if not slot.opened or not slot.rune_id.is_empty() or rune == null or rune.location != profile.location or rune.slot != slot_index:
					return DomainResult.failure(&"austin.rune", "请开启空槽并选择该装备此孔位的专属符文")
				amount = rules.inlay_cost
				slot.rune_id = rune_id
				slot.bound = rune_bound
				requirements.append({"definition_id": rune_id, "quantity": 1})
	requirements.append({"definition_id": rules.materials[material], "quantity": amount})
	if space > 0: requirements.append({"definition_id": rules.materials.space_crystal, "quantity": space})
	return DomainResult.ok(requirements)


## 序列化原始事实，避免保存重复派生的属性。
## 返回与内部状态脱离的字典，新装备为空对象。
func to_dictionary() -> Dictionary:
	var values: Array[Dictionary] = []
	var changed := color + stage + base + additional > 0 or blessed
	for slot: Slot in slots:
		values.append({"opened": slot.opened, "rune_id": slot.rune_id, "bound": slot.bound})
		changed = changed or slot.opened
	return {"version": 1, "color": color, "stage": stage, "base": base, "additional": additional, "blessed": blessed, "slots": values} if changed else {}


## 统一拒绝超过原版上限及重复祝福。
## 返回成长上限错误。
static func _maximum() -> DomainResult:
	return DomainResult.failure(&"austin.maximum", "此项已达上限或已完成祝福")


## 统一拒绝非法跨系列或槽位状态。
## 返回状态错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"austin.state", "奥斯格兰成长或符文状态无效")
