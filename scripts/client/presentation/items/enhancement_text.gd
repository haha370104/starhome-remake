class_name EnhancementText
extends RefCounted

const PREFIX_NAMES := {"tiger": "虎", "turtle": "龟", "dragon": "龙", "phoenix": "凤"}
const TRAIT_NAMES := {"economy": "节能", "repair": "稳修", "pursuit": "追击", "purification": "净化", "prospecting": "勘探"}
const ATTRIBUTES := {"max_health": "战车生命", "defense": "防御", "movement_speed": "移速",
	"energy_cannon_attack": "能量炮攻击", "missile_attack": "导弹攻击", "rocket_attack": "火箭炮攻击",
	"self_repair": "自维修力", "mining_power": "挖掘力", "working_energy_capacity": "工作能量上限",
	"output_power": "输出功率", "energy_cannon_range": "能量炮射程"}


## 由原名和实例词条形成展示名，不改写物品定义或持久化身份。
## [param name] 基础名称。
## [param raw] 已验证快照中的强化状态。
## 返回带前后缀的可读装备名。
static func title(name: String, raw: Dictionary) -> String:
	var prefix := String(raw.get("prefix", ""))
	var suffix := String(raw.get("trait", ""))
	return (String(PREFIX_NAMES.get(prefix, "")) + "·" if not prefix.is_empty() else "") + name + ("·" + String(TRAIT_NAMES.get(suffix, "")) if not suffix.is_empty() else "")


## 展示当前三条独立强化路线及效果。
## [param raw] 服务端强化状态。
## 返回多行说明，空路线明确标为未镶嵌。
static func describe(raw: Dictionary) -> String:
	var restored := ClothingEnhancement.restore(raw)
	if not restored.is_ok:
		return "强化状态不可用"
	var state: ClothingEnhancement = restored.value
	var result := PackedStringArray()
	result.append("前缀：" + (_effect("prefix", state.prefix, state.prefix_quality) if state.prefix_quality > 0 else "未刻印"))
	result.append("特性：" + (_effect("trait", state.trait_id, state.trait_quality) if state.trait_quality > 0 else "未刻印"))
	if state.gem_stage > 0:
		var rules: ClothingEnhancementRules = ClothingEnhancementRules.load_default().value
		result.append("宝石：%s %d段（+%s）" % [ATTRIBUTES.get(state.gem, state.gem), state.gem_stage, _number(rules.gem_increment(state.gem) * state.gem_stage)])
		result.append("下一段需要：%d级或更高的同类宝石" % (state.gem_stage + 1) if state.gem_stage < 15 else "宝石路线已满15段")
	else:
		result.append("宝石：未镶嵌，首次仅增加1段")
	return "\n".join(result)


## 解释材料实际用途，级别不等于一次增加的段数。
## [param row] 材料物品视图。
## 返回材料效果说明。
static func stone_description(row: Dictionary) -> String:
	var stone: Dictionary = row.get("enhancement_stone", {})
	var family := String(stone.get("family", ""))
	var effect := String(stone.get("effect", ""))
	var rank := int(stone.get("rank", 0))
	if family == "gem":
		var rules: ClothingEnhancementRules = ClothingEnhancementRules.load_default().value
		return "%d级%s宝石\n每段 +%s；每次仅提升1段。\n材料等级须不低于目标段数。" % [rank, ATTRIBUTES.get(effect, effect), _number(rules.gem_increment(effect))]
	return _effect(family, effect, rank)


## 通过领域规则查询指定品质的效果，不在界面复制数值表。
## [param family] 前缀或特性。
## [param effect] 效果身份。
## [param rank] 品质一至六。
## 返回品质、名称与效果。
static func _effect(family: String, effect: String, rank: int) -> String:
	if rank < 1 or rank > 6:
		return "无"
	var rules: ClothingEnhancementRules = ClothingEnhancementRules.load_default().value
	var quality := String(ClothingEnhancement.QUALITIES[rank - 1])
	if family == "prefix":
		var bonuses := ClothingBonuses.new()
		rules.apply_prefix(bonuses, effect, rank)
		var positive := String({"tiger": "max_health", "turtle": "defense", "dragon": "energy_cannon_attack", "phoenix": "movement_speed"}.get(effect, ""))
		var negative := String({"tiger": "energy_cannon_attack", "turtle": "movement_speed", "dragon": "defense", "phoenix": "max_health"}.get(effect, ""))
		var gain := bonuses.apply_value(positive, 100) - 100
		var loss := -bonuses.apply_value(negative, 0)
		var gain_name := "三类武器攻击" if effect == "dragon" else String(ATTRIBUTES.get(positive, positive))
		var loss_name := "三类武器攻击" if effect == "tiger" else String(ATTRIBUTES.get(negative, negative))
		return "%s·%s\n%s +%s%%，%s -%s" % [quality, PREFIX_NAMES.get(effect, effect), gain_name, _number(gain), loss_name, _number(loss)]
	var value := rules.trait_value(effect, rank)
	var descriptions := {"economy": "武器工作能量消耗 -%s%%" % _number(value * 100),
		"repair": "受击后的维修等待缩短 %s秒" % _number(value),
		"pursuit": "同武器同目标每第4击伤害 +%s%%" % _number(value * 100),
		"purification": "腐蚀持续伤害 -%s%%" % _number(value * 100),
		"prospecting": "%s%%概率额外采出1份，消耗矿量" % _number(value * 100)}
	return "%s·%s\n%s" % [quality, TRAIT_NAMES.get(effect, effect), descriptions.get(effect, "")]


## 以紧凑格式显示配置数值。
## [param value] 属性值。
## 返回整数或一位小数。
static func _number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
