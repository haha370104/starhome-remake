class_name VehicleEquipment
extends Equipment

var equipment_location: int
var equip_kind: int
var weight: int
var _device_kind: String
var attachment_family: String
var allowed_locations: Array = []
var sockets := VehicleSockets.new()
var socket_rules: VehicleSocketRules
var generator_profile: GeneratorRules.Profile
var crystal_source := CrystalSourceGrowth.new()
var crystal_source_profile: CrystalSourceRules.Profile
var crystal_source_rules: CrystalSourceRules
var austin_glens := AustinGlensGrowth.new()
var austin_profile: AustinGlensRules.Profile
var austin_rules: AustinGlensRules
var sama := SamaGrowth.new()
var sama_profile: SamaRules.Profile
var sama_rules: SamaRules
var central_growth := CentralGrowth.new()
var central_profile: CentralRules.Profile
var central_rules: CentralRules


## 汇总特殊系列的常驻属性，损坏装备不参与计算。
## [param attribute] 战车统一属性。
## 返回固定加值，随后由战车统一应用人物、食品等倍率。
func special_bonus(attribute: String) -> int:
	if durability <= 0: return 0
	var bonus := crystal_source.bonus(attribute, crystal_source_profile, crystal_source_rules) if crystal_source_profile != null else 0
	if austin_profile != null: bonus += austin_glens.bonus(attribute, austin_rules)
	if sama_profile != null: bonus += sama.bonus(attribute, sama_rules)
	if central_profile != null: bonus += central_growth.bonus(attribute, central_profile, central_rules)
	return bonus


## 同时服务手动装配与整套方案的特殊装备综合等级资格。
## [param player_level] 玩家综合等级。[param central_evolved] 角色中枢是否已进化。
## 返回可装配或具体等级不足原因。
func validate_owner_level(player_level: int, central_evolved: bool = false) -> DomainResult:
	if central_profile != null and not central_evolved:
		return DomainResult.failure(&"central.equipment_locked", "须先将中枢核心进化为圣焱型，才能装配附属装备")
	if crystal_source_profile != null and player_level < crystal_source_rules.required_level:
		return DomainResult.failure(&"equipment.level", "晶源体需要综合等级 %d" % crystal_source_rules.required_level)
	return DomainResult.ok()


## 汇总当前发生器的常驻属性，损坏时不提供能力。
## [param attribute] 战车统一属性名。
## 返回实际常驻加值。
func generator_bonus(attribute: String) -> int:
	return generator_profile.passive_bonus(attribute) if generator_profile != null and durability > 0 else 0


## 检查接合器逐级强化条件；不改变耐久、绑定和槽位。
## [param target_level] 本次目标等级。
## 返回允许强化或锁定、类型、等级错误。
func validate_attachment_upgrade(target_level: int) -> DomainResult:
	if attachment_family not in ["new_joint", "old_joint"]:
		return DomainResult.failure(&"upgrade.unsupported", "该装备不支持接合器强化")
	if locked:
		return DomainResult.failure(&"upgrade.locked", "请先解除接合器锁定")
	var maximum := 5 if attachment_family == "new_joint" else 4
	var values: Array = stat("attachment_values", [])
	if target_level != upgrade_level + 1 or target_level > maximum or target_level >= values.size():
		return DomainResult.failure(&"upgrade.max_level", "该接合器已达强化上限或阶段未开放")
	return DomainResult.ok()


## 在玩家聚合完成支付后推进一级强化，保持实例身份和其他装备状态。
## [param target_level] 经过相同实例预检的目标等级。
## 返回升级后的等级或拒绝原因。
func upgrade_attachment(target_level: int) -> DomainResult:
	var checked := validate_attachment_upgrade(target_level)
	if not checked.is_ok:
		return checked
	upgrade_level = target_level
	return DomainResult.ok(upgrade_level)


## 查询当前强化等级的装置效果，损坏装备不提供加值。
## [param effect] 规范化效果标识。
## 返回该装备贡献的固定加值。
func attachment_bonus(effect: String) -> int:
	if durability <= 0 or String(stat("attachment_effect", "")) != effect:
		return 0
	var values: Array = stat("attachment_values", [])
	return int(values[mini(upgrade_level, values.size() - 1)]) if not values.is_empty() else 0


## 初始化安装到战车固定 Location 的装备实例。
## [param definition] 战车装备定义。
## [param state] 存档中的装备实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	var restored_central := CentralGrowth.restore(state.get("central_growth", {}))
	if restored_central.is_ok: central_growth = restored_central.value
	var restored_sama := SamaGrowth.restore(state.get("sama", {}))
	if restored_sama.is_ok: sama = restored_sama.value
	var restored_source := CrystalSourceGrowth.restore(state.get("crystal_source", {}))
	if restored_source.is_ok: crystal_source = restored_source.value
	var restored_austin := AustinGlensGrowth.restore(state.get("austin_glens", {}))
	if restored_austin.is_ok: austin_glens = restored_austin.value
	equipment_location = int(definition.get("equipment_location", -1))
	allowed_locations = definition.get("allowed_locations", [equipment_location]).duplicate()
	attachment_family = String(definition.get("attachment_family", ""))
	var restored_location := int(state.get("equipment_location", equipment_location))
	if restored_location in allowed_locations:
		equipment_location = restored_location
	equip_kind = int(definition.get("equip_kind", -1))
	_device_kind = String(definition.get("kind", ""))
	weight = maxi(0, int(stat("weight", 0)))


## 判断装备是否接受指定的战车 Location。
## [param location] 荣耀客户端稳定槽位编号。
## 返回目标与定义 Location 一致时为 true。
func accepts_location(location: int) -> bool:
	return location in allowed_locations


## 查询主装置的业务类型，供 HUD 和输入路由共享，避免各处解释旧客户端字段。
## 返回能量炮、采掘臂、维修臂的语义标识；非主装置或未知类型返回空字符串。
func primary_device_kind() -> String:
	if equipment_location != 1:
		return ""
	match _device_kind:
		"mining_arm", "repair_arm":
			return _device_kind
		"energy_cannon", "vehicle_weapon":
			return "energy_cannon"
	return ""


## 导出带固定 Location 的战车装备视图。
## 返回通用装备 DTO 加战车槽位信息。
func to_view_dictionary() -> Dictionary:
	var view := super()
	view["central_growth"] = central_growth.to_dictionary()
	view["central_eligible"] = central_profile != null
	if central_profile != null:
		view.description += "\n圣焱附属装备：%d / 18阶" % central_growth.grade
		for attribute: String in ["max_health", "energy_cannon_attack", "missile_attack"]:
			view.description += "\n%s +%d" % [{"max_health":"战车生命", "energy_cannon_attack":"能量炮攻击", "missile_attack":"导弹攻击"}[attribute], special_bonus(attribute)]
	view["sama"] = sama.to_dictionary()
	view["sama_eligible"] = sama_profile != null
	if sama_profile != null:
		view.display_name = "[%s] %s" % [["白色", "绿色", "蓝色", "紫色"][sama.color], display_name]
		view.description += "\n" + sama.description(sama_profile, sama_rules)
	view["austin_glens"] = austin_glens.to_dictionary()
	view["austin_eligible"] = austin_profile != null
	if austin_profile != null:
		view.description += "\n奥斯格兰：%s；阶段%d；基础%d；附加%d；%s" % [["白色", "绿色", "蓝色", "紫色"][austin_glens.color], austin_glens.stage, austin_glens.base, austin_glens.additional, "已祝福" if austin_glens.blessed else "未祝福"]
		for attribute: String in AustinGlensRules.ATTRIBUTES:
			var bonus := special_bonus(attribute)
			if bonus > 0: view.description += "\n%s +%d" % [{"max_health": "战车生命", "defense": "防御", "energy_cannon_attack": "能量炮攻击", "missile_attack": "导弹攻击", "self_repair_bonus": "额外自维修"}[attribute], bonus]
		view.description += "\n固定左右符文，镶入后不能摘取。\n穿透值%d：原版对怪物结算未确认，暂不提供PVE减防。" % austin_glens.bonus("penetration", austin_rules)
		if austin_profile.effect in ["mitigation", "healing"]:
			view.description += "\n受直接攻击有%.0f%%概率%s%d点，每%d秒最多一次。" % [austin_rules.trigger_chance * 100, "减伤" if austin_profile.effect == "mitigation" else "存活时回血", austin_rules.mitigation[austin_glens.additional] if austin_profile.effect == "mitigation" else austin_rules.healing[austin_glens.additional], austin_rules.cooldown_seconds]
		else:
			view.description += "\n附加追伤只对其他玩家生效，本轮未开放；常驻属性正常生效。"
		view.description += "\n四件套额外触发只对其他玩家生效，暂未开放。"
	view["crystal_source"] = crystal_source.to_dictionary()
	view["crystal_source_eligible"] = crystal_source_profile != null
	if crystal_source_profile != null:
		view["description"] = String(view.description) + "\n晶源体品质 %d / 15；成长 %d / 15；综合等级要求 %d\n独立三核槽，每种颜色限一枚。" % [crystal_source.quality, crystal_source.growth, crystal_source_rules.required_level]
		for attribute: String in ["max_health", "energy_cannon_attack", "rocket_attack", "missile_attack"]:
			var bonus := special_bonus(attribute)
			if bonus > 0:
				view.description += "\n%s +%d" % [{"max_health": "战车生命", "energy_cannon_attack": "能量炮攻击", "rocket_attack": "火箭攻击", "missile_attack": "导弹攻击"}[attribute], bonus]
	if generator_profile != null:
		view["description"] = String(view.get("description", "")) + "\n\n" + generator_profile.description()
		view["generator_effects"] = generator_profile.description()
	if _definition.has("pve_scope_notice"):
		view["description"] = String(view.get("description", "")) + "\n\n" + String(_definition.pve_scope_notice)
	view["equipment_location"] = equipment_location
	view["location"] = equipment_location
	view["equip_kind"] = equip_kind
	view["attachment_family"] = attachment_family
	view["allowed_locations"] = allowed_locations.duplicate()
	view["vehicle_sockets"] = sockets.to_dictionary()
	view["socket_eligible"] = socket_rules != null and socket_rules.profile(definition_id) != null
	return view
