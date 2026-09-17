class_name ArmorRefinement
extends RefCounted


## 为护甲换代产生新的原始状态，保留磨损量、维护损失及全部已存在孔槽。
## [param armor] 当前护甲。
## [param target] 下一阶的目录默认实例。
## [param bound_material] 是否消费绑定材料或赠品装备。
## 返回待目录严格校验的状态，不修改旧装备与目标模板。
## 设计：原客户端没有下发转换算法，保留成长与磨损的策略为复刻约定。
static func replacement_state(armor: VehicleEquipment, target: VehicleEquipment, bound_material: bool) -> DomainResult:
	if armor == null or target == null or armor.equipment_location != target.equipment_location:
		return DomainResult.failure(&"armor_refinement.replacement", "护甲换代部位不匹配")
	var state := armor.to_view_dictionary()
	var target_maximum := target.max_durability
	var old_base := int(armor.stat("max_durability", armor.max_durability))
	var maintenance_loss := maxi(0, old_base - armor.max_durability)
	state["max_durability"] = maxi(1, target_maximum - maintenance_loss)
	state["durability"] = maxi(1, int(state.max_durability) - (armor.max_durability - armor.durability))
	state["bound"] = armor.bound or bound_material
	var sockets := armor.sockets.to_dictionary()
	if sockets.is_empty(): sockets = {"version": 1, "slots": []}
	var target_profile := target.socket_rules.profile(target.definition_id)
	var maximum := target_profile.maximum_capacity if target_profile != null else 0
	var minimum := target_profile.base_capacity if target_profile != null else 0
	if sockets.slots.size() > maximum:
		return DomainResult.failure(&"armor_refinement.sockets", "目标孔数不足，无法完整保留现有晶石")
	while sockets.slots.size() < minimum:
		sockets.slots.append(VehicleSocket.new().to_dictionary())
	state["vehicle_sockets"] = sockets
	return DomainResult.ok(state)
