class_name ArmorRefinementRules
extends RefCounted

class Profile extends RefCounted:
	var definition_id: String
	var display_name: String
	var level: int
	var location: int
	var next_definition_id: String
	var gift_bound: bool

var profiles: Dictionary[String, Profile] = {}
var currency: int
var _chip_chances: Array[float] = []
var _stone_chances: Array[float] = []


## 编译护甲精工资格，阶级由原装备定义表达，不复用任何实例强化等级。
## [param raw] 版本化原版规则。
## 返回通过类型和相邻阶级校验的规则目录。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	if raw.get("schema_version") != 1 or raw.get("maximum_level") != 8 or raw.get("failure") != "destroy_equipment":
		return DomainResult.failure(&"armor_refinement.rules", "护甲精工规则版本无效")
	var rules := ArmorRefinementRules.new()
	rules.currency = int(raw.get("currency", -1))
	if rules.currency < 0: return DomainResult.failure(&"armor_refinement.rules", "护甲精工费用无效")
	for key: String in ["chip_chances", "stone_chances"]:
		var bands: Array[float] = []
		for value: float in raw.get(key, []):
			if not is_finite(value) or value <= 0 or value > 1:
				return DomainResult.failure(&"armor_refinement.rules", "护甲精工成功率无效")
			bands.append(value)
		if bands.size() != (10 if key == "chip_chances" else 4) or bands[-1] != 1.0:
			return DomainResult.failure(&"armor_refinement.rules", "护甲精工成功率档数无效")
		if key == "chip_chances": rules._chip_chances = bands
		else: rules._stone_chances = bands
	for row: Dictionary in raw.get("equipment", []):
		var profile := Profile.new()
		profile.definition_id = String(row.get("definition_id", ""))
		profile.display_name = String(row.get("display_name", ""))
		profile.level = int(row.get("level", 0))
		profile.location = int(row.get("location", 0))
		profile.next_definition_id = String(row.get("next_definition_id", ""))
		profile.gift_bound = bool(row.get("gift_bound", false))
		if profile.definition_id.is_empty() or rules.profiles.has(profile.definition_id) or profile.level < 1 or profile.level > 8 \
			or profile.location < 5 or profile.location > 8 or profile.next_definition_id.is_empty() != (profile.level == 8):
			return DomainResult.failure(&"armor_refinement.rules", "护甲精工资格无效")
		rules.profiles[profile.definition_id] = profile
	for profile: Profile in rules.profiles.values():
		if profile.level == 8: continue
		var target: Profile = rules.profiles.get(profile.next_definition_id)
		if target == null or target.level != profile.level + 1 or target.location != profile.location:
			return DomainResult.failure(&"armor_refinement.rules", "护甲精工目标并非同部位下一阶")
	return DomainResult.ok(rules)


## 按当前阶级和材料部位报价，四阶以上必须使用相应精工石。
## [param profile] 装备原始资格。
## [param material] 类型化精工材料。
## [param quantity] 选定材料的投入颗数。
## 返回升级定义、概率和全部消耗，或不兼容原因。
func preview(profile: Profile, material: ArmorRefinementMaterial, quantity: int) -> DomainResult:
	if profile == null: return DomainResult.failure(&"armor_refinement.target", "该护甲不支持原版精工")
	if profile.level == 8: return DomainResult.failure(&"armor_refinement.maximum", "护甲已达到第八阶")
	var location := profile.location if profile.level >= 4 else 0
	if material == null or material.refinement_location != location:
		return DomainResult.failure(&"armor_refinement.material", "前三阶使用精工芯片，第四阶起使用对应部位精工石")
	if quantity < 1 or quantity > (4 if profile.level >= 4 else 99):
		return DomainResult.failure(&"armor_refinement.quantity", "芯片每次1～99个；对应部位精工石每次1～4个")
	var bands := _stone_chances if profile.level >= 4 else _chip_chances
	var requirements: Array[Dictionary] = [{"definition_id": material.definition_id, "quantity": quantity}]
	return DomainResult.ok({"before": profile.level, "after": profile.level + 1,
		"next_definition_id": profile.next_definition_id, "chance": bands[mini(quantity - 1, bands.size() - 1)],
		"requirements": requirements, "currency": currency})
