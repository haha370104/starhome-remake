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
	if generator_profile != null:
		view["description"] = String(view.get("description", "")) + "\n\n" + generator_profile.description()
		view["generator_effects"] = generator_profile.description()
	view["equipment_location"] = equipment_location
	view["location"] = equipment_location
	view["equip_kind"] = equip_kind
	view["attachment_family"] = attachment_family
	view["allowed_locations"] = allowed_locations.duplicate()
	view["vehicle_sockets"] = sockets.to_dictionary()
	view["socket_eligible"] = socket_rules != null and socket_rules.profile(definition_id) != null
	return view
