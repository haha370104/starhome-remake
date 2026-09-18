class_name SamaGrowth
extends RefCounted

var color := 0
var growth := 0
var quality := 0


## 恢复独立成长事实，缺失字段的旧装备使用白色零成长。
## [param raw] 存档边界。
## 返回合法实例或状态错误。
static func restore(raw: Variant) -> DomainResult:
	var value := SamaGrowth.new()
	if not raw is Dictionary: return _invalid()
	if raw.is_empty(): return DomainResult.ok(value)
	if raw.get("version") != 1: return _invalid()
	for key: String in ["color", "growth", "quality"]:
		if not SamaRules.integer(raw.get(key), 0, 3 if key == "color" else 10): return _invalid()
		value.set(key, int(raw[key]))
	if value.growth > [1, 3, 6, 10][value.color] or value.quality > value.growth: return _invalid()
	return DomainResult.ok(value)


## 检查状态归属，避免普通装备携带隐藏撒玛成长。
## [param profile] 目标定义的规则。
## 返回合法或跨系列状态错误。
func validate_for(profile: SamaRules.Profile) -> DomainResult:
	return _invalid() if profile == null and not to_dictionary().is_empty() else DomainResult.ok()


## 计算单件常驻属性，磨损生效条件由装备模型统一管理。
## [param attribute] 战车属性。[param rules] 缩放后的规则。
## 返回单件固定加值。
func bonus(attribute: String, rules: SamaRules) -> int:
	if attribute not in SamaRules.ATTRIBUTES: return 0
	if attribute == "max_health": return rules.color_health[color] + growth * rules.growth_health + quality * rules.quality_health
	return rules.color_attack[color] + growth * rules.growth_attack + quality * rules.quality_attack


## 确定本件装备能量炮触发概率，维持原版颜色及品质曲线。
## [param rules] 原版概率配置。
## 返回零到一的概率。
func chance(rules: SamaRules) -> float:
	return float(rules.chance_percent[color] + quality) / 100.0


## 确定聚能与核变状态的实际时长。
## [param rules] 原版时长配置。
## 返回持续秒数。
func duration(rules: SamaRules) -> int:
	return rules.duration_seconds[color] + rules.duration_additions[quality]


## 确定脉冲或核变的追加伤害，不递归触发普通武器能力。
## [param effect] 脉冲或核变标识。[param rules] 缩放后的伤害表。
## 返回追加固定伤害。
func damage(effect: String, rules: SamaRules) -> int:
	if effect not in ["pulse", "fission"]: return 0
	return rules.damage_base[color] + (rules.pulse_additions[quality] if effect == "pulse" else rules.fission_additions[quality])


## 对独立候选推进一级阶段或品质，拒绝越过颜色与阶段上限。
## [param mode] growth或quality。[param rules] 材料规则。
## 返回需要支付的材料清单。
func advance(mode: String, rules: SamaRules) -> DomainResult:
	var count := 0
	match mode:
		"growth":
			if growth >= rules.color_caps[color]: return DomainResult.failure(&"sama.maximum", "已达此颜色的成长阶段上限")
			count = rules.growth_costs[growth]
			growth += 1
		"quality":
			if quality >= growth: return DomainResult.failure(&"sama.quality", "品质等级不能超过成长阶段，请先提升阶段")
			count = rules.quality_cost
			quality += 1
		_: return _invalid()
	return DomainResult.ok([{"definition_id": rules.materials[mode], "quantity": count}])


## 将源装备成长覆盖到同色或更高色的独立目标候选。
## [param donor] 将被销毁的来源成长。
## 返回接受转移或不满足颜色/成长条件的拒绝。
func receive(donor: SamaGrowth) -> DomainResult:
	if donor == null or donor == self or donor.growth <= 0 or color < donor.color:
		return DomainResult.failure(&"sama.transfer", "源装备须有成长阶段，目标颜色不能低于源装备")
	growth = donor.growth
	quality = donor.quality
	return DomainResult.ok()


## 序列化成长事实，不把派生属性和战斗临时状态写入装备。
## 返回独立JSON字典。
func to_dictionary() -> Dictionary:
	return {"version": 1, "color": color, "growth": growth, "quality": quality} if color + growth + quality > 0 else {}


## 说明此装备的实际缩放属性与适用技能，不把原版大数值混入面板。
## [param profile] 当前部件。[param rules] 当前平衡表。
## 返回供物品视图和工坊共同使用的说明。
func description(profile: SamaRules.Profile, rules: SamaRules) -> String:
	var text := "撒玛：%s；阶段 %d/%d；品质 %d/%d" % [["白色", "绿色", "蓝色", "紫色"][color], growth, rules.color_caps[color], quality, growth]
	text += "\n战车生命 +%d；防御 +%d\n能量炮攻击 +%d；导弹攻击 +%d" % [bonus("max_health", rules), bonus("defense", rules), bonus("energy_cannon_attack", rules), bonus("missile_attack", rules)]
	if profile.effect == "pvp_absorption": return text + "\n扰流吸收仅对其他玩家生效，本轮暂未开放。"
	text += "\n能量炮开火时 %.0f%% 概率：" % (chance(rules) * 100)
	match profile.effect:
		"piercing": text += "聚能穿透，持续%d秒；子弹穿透目标直到射程终点。" % duration(rules)
		"pulse": text += "脉冲攻击，前方%d×%d范围造成%d伤害。" % [rules.pulse_range, rules.pulse_range, damage("pulse", rules)]
		"fission": text += "核变反应，持续%d秒；能量炮命中追加%d伤害。" % [duration(rules), damage("fission", rules)]
	return text


## 拒绝无效成长状态。
## 返回领域错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"sama.state", "撒玛颜色、阶段或品质状态无效")
