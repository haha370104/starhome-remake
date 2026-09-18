class_name CentralGrowth
extends RefCounted

var grade := 0


## 恢复圣焱附属装备的独立阶数；旧存档默认零阶。
## [param raw] 持久化边界。
## 返回成长状态或拒绝非法阶数。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary or not CentralRules.integer(raw.get("grade", 0), 0, 18):
		return DomainResult.failure(&"central.growth_state", "中枢装备阶数无效")
	var growth := CentralGrowth.new()
	growth.grade = int(raw.get("grade", 0))
	return DomainResult.ok(growth)


## 验证成长事实没有落入不相关装备。
## [param profile] 目录确认的系列资格。
## 返回有效或跨系列状态错误。
func validate_for(profile: CentralRules.Profile) -> DomainResult:
	if profile == null and grade != 0: return DomainResult.failure(&"central.wrong_item", "该物品不支持圣焱装备成长")
	return DomainResult.ok()


## 推进一阶并给出本阶必须消耗的原版材料。
## [param rules] 核查规则。
## 返回一份材料要求；满阶失败时状态不变。
func advance(rules: CentralRules) -> DomainResult:
	if grade >= 18: return DomainResult.failure(&"central.max_grade", "圣焱装备已达18阶")
	var material := rules.growth_materials[floori(grade / 3.0)]
	grade += 1
	return DomainResult.ok([{"definition_id": material, "quantity": 1}])


## 汇总单件装备基础属性和阶数增量。
## [param attribute] 战车属性。[param profile] 部件定义。[param rules] 成长规则。
## 返回固定属性值。
func bonus(attribute: String, profile: CentralRules.Profile, rules: CentralRules) -> int:
	var value := int(profile.base.get(attribute, 0))
	if attribute == "max_health": value += rules.health_increments[grade]
	elif attribute in ["energy_cannon_attack", "missile_attack"]: value += rules.attack_increments[grade]
	return value


## 选择原版在当前阶数指定的图标。
## [param profile] 含源版本图标切换表的定义。
## 返回独立表现数据副本。
func presentation(profile: CentralRules.Profile) -> Dictionary:
	var chosen: Dictionary = profile.visuals[0]
	for visual: Dictionary in profile.visuals:
		if int(visual.grade) <= grade: chosen = visual
	return chosen.duplicate(true)


## 导出唯一需要保存的成长事实。
## 返回阶数数据。
func to_dictionary() -> Dictionary:
	return {"grade": grade}
