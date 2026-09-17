class_name GeneratorRules
extends RefCounted

class Profile extends RefCounted:
	var definition_id := ""
	var label := ""
	var working_energy_cost := 0.0
	var cooldown_seconds := 0.0
	var chance := 0.0
	var duration_seconds := 0.0
	var heat_damage := 0
	var defense_flat_reduction := 0
	var defense_percent_reduction := 0.0
	var attack_percent_reduction := 0.0
	var energy_attack_percent_reduction := 0.0
	var max_health := 0
	var defense := 0
	var energy_cannon_attack := 0

	## 按统一属性名投影常驻增益，不叠加尚未接入的专属品质。
	## [param attribute] 战车属性名。
	## 返回原版基础加值。
	func passive_bonus(attribute: String) -> int:
		match attribute:
			"max_health": return max_health
			"defense": return defense
			"energy_cannon_attack": return energy_cannon_attack
		return 0

	## 描述当前已接通的常驻和命中效果，并标明未核实的目标范围。
	## 返回用于装备详情的纯文本。
	func description() -> String:
		var lines: Array[String] = []
		for field: String in ["max_health", "defense", "energy_cannon_attack"]:
			if passive_bonus(field) > 0:
				lines.append("%s +%d" % [{"max_health": "战车生命", "defense": "战车防御", "energy_cannon_attack": "能量炮攻击"}[field], passive_bonus(field)])
		if chance > 0:
			lines.append("能量炮命中时 %.0f%% 触发，持续 %s 秒" % [chance * 100, str(duration_seconds)])
			if heat_damage > 0: lines.append("高热：每秒 %d 伤害" % heat_damage)
			if defense_flat_reduction > 0: lines.append("蚀甲：防御 -%d" % defense_flat_reduction)
			if defense_percent_reduction > 0: lines.append("腐蚀：防御 -%.0f%%" % (defense_percent_reduction * 100))
			if attack_percent_reduction > 0: lines.append("磁化：攻击 -%.0f%%" % (attack_percent_reduction * 100))
			if energy_attack_percent_reduction > 0: lines.append("能量炮压制 %.0f%%：当前怪物武器类型未核实，暂不生效" % (energy_attack_percent_reduction * 100))
			lines.append("触发消耗 1 发弹药、%s 工作能量；冷却 %s 秒" % [str(working_energy_cost), str(cooldown_seconds)])
		lines.append("发生器最多装备两件；同类临时效果取最强值")
		return "\n".join(lines)

var profiles: Dictionary[String, Profile] = {}


## 验证发生器配置并将边界字典转为具名效果，不在战斗循环解释原版字段。
## [param raw] 版本化只读配置。
## 返回类型化规则或具体错误。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	var rules := GeneratorRules.new()
	if raw.get("schema_version") != 1 or not raw.get("equipment") is Array:
		return DomainResult.failure(&"generator.rules", "发生器规则版本或列表无效")
	for row: Variant in raw.equipment:
		if not row is Dictionary: return DomainResult.failure(&"generator.rules", "发生器配置必须为对象")
		var profile := Profile.new()
		profile.definition_id = String(row.get("definition_id", ""))
		profile.label = String(row.get("label", ""))
		if profile.definition_id.is_empty() or profile.label.is_empty() or rules.profiles.has(profile.definition_id):
			return DomainResult.failure(&"generator.rules", "发生器身份无效或重复")
		for field: String in ["working_energy_cost", "cooldown_seconds", "chance", "duration_seconds", "heat_damage", "defense_flat_reduction", "defense_percent_reduction", "attack_percent_reduction", "energy_attack_percent_reduction", "max_health", "defense", "energy_cannon_attack"]:
			var value: Variant = row.get(field)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0:
				return DomainResult.failure(&"generator.rules", "发生器数值无效：" + field)
			if field in ["chance", "defense_percent_reduction", "attack_percent_reduction", "energy_attack_percent_reduction"] and float(value) > 1:
				return DomainResult.failure(&"generator.rules", "发生器比例超出范围")
			if field in ["heat_damage", "defense_flat_reduction", "max_health", "defense", "energy_cannon_attack"]:
				if float(value) != floorf(float(value)): return DomainResult.failure(&"generator.rules", "发生器固定数值必须为整数")
				profile.set(field, int(value))
			else: profile.set(field, float(value))
		if profile.chance > 0 and profile.duration_seconds <= 0:
			return DomainResult.failure(&"generator.rules", "发生器触发效果缺少持续时间")
		rules.profiles[profile.definition_id] = profile
	return DomainResult.ok(rules)
