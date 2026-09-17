class_name EquipmentTooltipFormatter
extends RefCounted

const STAT_NAMES := {
	"required_skill_level": "需求技能等级",
	"purchase_value": "购买价",
	"sell_value": "出售值",
	"weight": "重量",
	"max_health": "生命值",
	"max_health_limit": "极限生命",
	"armor": "防御力",
	"drive": "推进力",
	"drive_limit": "极限推进力",
	"base_attack": "攻击力",
	"attack_limit": "极限攻击力",
	"working_energy_per_shot": "功耗",
	"working_energy_cost": "工作能量消耗",
	"range": "射程",
	"range_limit": "极限射程",
	"output_power": "输出功率",
	"output_power_limit": "极限输出功率",
	"clothing_class": "服装等级",
	"wear_damage_per_hit": "受击损耗",
}


## 按旧客户端物品说明顺序构造装备悬浮文本。
## [param equipment] 权威快照中的装备表现与属性字典。
## [param action_hint] 提示框末尾的交互说明；装备槽与背包可传入不同文案。
## 返回名称、说明、有效属性和耐久组成的多行文本。
static func format(equipment: Dictionary, action_hint: String = "双击卸下") -> String:
	var lines := PackedStringArray()
	lines.append(EnhancementText.title(String(equipment.get("display_name", "未知装备")), equipment.get("enhancement", {})))
	var description := String(equipment.get("description", ""))
	if not description.is_empty():
		lines.append(description)
	var stats: Dictionary = equipment.get("stats", {})
	for stat_id: String in STAT_NAMES:
		if not stats.has(stat_id):
			continue
		lines.append("%s：%s" % [STAT_NAMES[stat_id], _format_number(stats[stat_id])])
	var modifiers: Dictionary = stats.get("skill_modifiers", {})
	for modifier_id: Variant in modifiers:
		lines.append("%s：+%s" % [String(modifier_id), _format_number(modifiers[modifier_id])])
	var durability := int(equipment.get("durability", 0))
	var maximum := int(equipment.get("max_durability", 0))
	if maximum > 0:
		lines.append("耐久：%d / %d" % [durability, maximum])
	if equipment.has("enhancement"):
		lines.append(EnhancementText.describe(equipment.enhancement))
	if equipment.has("clothing_improvement_summary"):
		lines.append(String(equipment.clothing_improvement_summary))
	if not action_hint.is_empty():
		lines.append(action_hint)
	return "\n".join(lines)


## 将整型或浮点型装备属性格式化为紧凑文本。
## [param value] 待显示的数值。
## 返回整数不带小数，其他数值保留一位小数。
static func _format_number(value: Variant) -> String:
	var number := float(value)
	if is_equal_approx(number, floorf(number)):
		return str(int(number))
	return "%.1f" % number
