class_name ClothingImprovement
extends RefCounted

var attribute := ""
var level := 0


## 严格恢复独立改良事实，旧档默认未改良。
## [param raw] 存档字典。
## 返回零到百级的成长对象或非法记录。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary or raw.get("version", 1) != 1:
		return DomainResult.failure(&"clothing_improvement.state", "服装改良记录无效")
	var count: Variant = raw.get("level", 0)
	var kind: Variant = raw.get("attribute", "")
	if not (count is int or count is float) or not is_finite(float(count)) or count != int(count) or count < 0 or count > 100 or not kind is String:
		return DomainResult.failure(&"clothing_improvement.state", "服装改良等级无效")
	if (count == 0) != kind.is_empty():
		return DomainResult.failure(&"clothing_improvement.state", "服装改良方向和等级不一致")
	var result := ClothingImprovement.new()
	result.level = int(count)
	result.attribute = kind
	return DomainResult.ok(result)


## 验证非零成长只能存在于允许改良的原版时装上。
## [param definition_id] 装备稳定定义。
## [param rules] 已验证目录。
## 返回合法事实或不兼容原因。
func validate_for(definition_id: String, rules: ClothingImprovementRules) -> DomainResult:
	return DomainResult.ok() if level == 0 or (rules.slots.has(definition_id) and rules.channels.has(attribute)) else DomainResult.failure(&"clothing_improvement.incompatible", "该服装或改良方向不受支持")


## 计算单方向逐级改良的材料、整数百分比和固定属性收益。
## [param definition_id] 当前时装定义。
## [param rules] 原版资格和属性目录。
## [param selected_attribute] 所选纤维的方向。
## [param quantity] 投入纤维总量，可跨同类堆叠。
## 返回完整预览或方向、数量错误。
func preview(definition_id: String, rules: ClothingImprovementRules, selected_attribute: String, quantity: int) -> DomainResult:
	if not rules.slots.has(definition_id):
		return DomainResult.failure(&"clothing_improvement.target", "仅原版季节时装支持纤维改良")
	if level >= 100: return DomainResult.failure(&"clothing_improvement.maximum", "服装改良已达100级")
	var channel: ClothingImprovementRules.Channel = rules.channels.get(selected_attribute)
	if channel == null or (level > 0 and attribute != selected_attribute):
		return DomainResult.failure(&"clothing_improvement.channel", "改良后只能继续使用相同种类的仿生纤维")
	var guaranteed := rules.guaranteed_quantities[floori(level / 5.0)]
	if quantity < 1 or quantity > guaranteed:
		return DomainResult.failure(&"clothing_improvement.quantity", "本阶段每次可投入1～%d份纤维" % guaranteed)
	var chance := mini(100, floori(quantity * 100.0 / guaranteed))
	if chance <= 0: return DomainResult.failure(&"clothing_improvement.chance", "投入数量不足，成功率会被取整为0%")
	var requirements: Array[Dictionary] = [{"definition_id": channel.material_id, "quantity": quantity}]
	return DomainResult.ok({"before": level, "after": level + 1, "attribute": channel.attribute,
		"attribute_label": channel.label, "bonus_before": channel.increment * level,
		"bonus_after": channel.increment * (level + 1), "chance": chance / 100.0,
		"guaranteed_quantity": guaranteed, "currency": 0,
		"requirements": requirements})


## 只在服务端确认支付可行后对候选结算；失败保留现有方向和等级。
## [param definition_id] 时装定义。
## [param rules] 改良规则。
## [param selected_attribute] 纤维方向。
## [param quantity] 本次投入。
## [param roll] 服务端随机样本。
## 返回实际等级与成功标志。
func apply(definition_id: String, rules: ClothingImprovementRules, selected_attribute: String, quantity: int, roll: float) -> DomainResult:
	if not is_finite(roll) or roll < 0 or roll >= 1:
		return DomainResult.failure(&"clothing_improvement.roll", "改良随机样本无效")
	var result := preview(definition_id, rules, selected_attribute, quantity)
	if not result.is_ok: return result
	result.value["success"] = roll < float(result.value.chance)
	if result.value.success:
		level += 1
		attribute = selected_attribute
	result.value["actual_level"] = level
	return result


## 导出独立改良事实，不重复保存派生属性。
## 返回版本、方向和等级。
func to_dictionary() -> Dictionary:
	return {"version": 1, "attribute": attribute, "level": level}
