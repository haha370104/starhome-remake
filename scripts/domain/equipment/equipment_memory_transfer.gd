class_name EquipmentMemoryTransfer
extends RefCounted

class Candidate extends RefCounted:
	var equipment: VehicleEquipment
	var module: EquipmentMemoryModule
	var discarded_rounds := 0


## 构造抽取成功候选，只清除一种成长并保留源装备与其他状态。
## [param equipment] 未锁定背包装备。
## [param module] 空白模块。
## [param catalog] 受控目录。
## [param bind_material] 稳压剂是否绑定。
## 返回两个完整候选实例或资格错误。
static func extract(equipment: VehicleEquipment, module: EquipmentMemoryModule, catalog: ItemCatalog, bind_material: bool) -> DomainResult:
	if not module.memory.source_definition_id.is_empty(): return DomainResult.failure(&"memory.loaded", "提取需要空白记忆模块")
	var profile: EquipmentMemoryRules.Profile = catalog.memory_rules.profiles.get(equipment.definition_id)
	if profile == null or module.module_type not in profile.extract_types:
		return DomainResult.failure(&"memory.extract_forbidden", "原版不允许该装备提取这种成长")
	var captured := EquipmentMemory.capture(equipment, module.module_type)
	if not captured.is_ok: return captured
	var item_state := equipment.to_view_dictionary()
	_remove_selected_growth(item_state, module.module_type)
	item_state.magazine = {"remaining": 0}
	var cleared := catalog.create(equipment.definition_id, item_state)
	if not cleared.is_ok:
		return DomainResult.failure(&"memory.remaining_growth", "提取后剩余成长将越过上限，请先提取普通加工：" + cleared.error_message)
	var cleared_item: VehicleEquipment = cleared.value
	cleared_item.magazine.remaining = mini(equipment.magazine.remaining, cleared_item.ammunition_capacity())
	var module_state := module.to_view_dictionary()
	module_state["equipment_memory"] = captured.value.to_dictionary()
	module_state["bound"] = equipment.bound or module.bound or bind_material or _has_bound_crystal(captured.value)
	var loaded := catalog.create(module.definition_id, module_state)
	if not loaded.is_ok: return loaded
	var result := Candidate.new()
	result.equipment = cleared_item
	result.discarded_rounds = equipment.magazine.remaining - cleared_item.magazine.remaining
	result.module = loaded.value
	return DomainResult.ok(result)


## 构造转移成功候选，目标必须同装备类型且所选成长为空，越界不截断。
## [param equipment] 目标背包装备。
## [param module] 已载入成长的模块。
## [param catalog] 权威目录。
## [param bind_material] 稳压剂绑定事实。
## 返回完整目标候选或不可转移原因。
static func transfer(equipment: VehicleEquipment, module: EquipmentMemoryModule, catalog: ItemCatalog, bind_material: bool) -> DomainResult:
	var memory := module.memory
	var source: EquipmentMemoryRules.Profile = catalog.memory_rules.profiles.get(memory.source_definition_id)
	var target: EquipmentMemoryRules.Profile = catalog.memory_rules.profiles.get(equipment.definition_id)
	if source == null or target == null or source.kind != target.kind or module.module_type not in target.transfer_types:
		return DomainResult.failure(&"memory.transfer_forbidden", "请选择兼容的同类装备与已载入模块")
	if EquipmentMemory.capture(equipment, module.module_type).is_ok:
		return DomainResult.failure(&"memory.occupied", "目标已有同类成长，请先提取，避免覆盖丢失")
	var state := equipment.to_view_dictionary()
	var growth := memory.equipment_state()
	if module.module_type in [3, 4]:
		var levels: Dictionary = state.extra_attributes.levels.duplicate()
		levels.merge(growth.extra_attributes.levels)
		growth.extra_attributes = {"version": 1, "levels": levels}
	elif module.module_type == 6:
		var slots: Array = growth.vehicle_sockets.slots
		var profile := catalog.socket_rules.profile(equipment.definition_id)
		if profile == null: return DomainResult.failure(&"memory.sockets", "目标不支持普通晶石孔")
		while slots.size() < profile.base_capacity: slots.append(VehicleSocket.new().to_dictionary())
	state.merge(growth, true)
	state["bound"] = equipment.bound or module.bound or bind_material or _has_bound_crystal(memory)
	var created := catalog.create(equipment.definition_id, state)
	if not created.is_ok: return DomainResult.failure(&"memory.target_limit", "目标无法完整承接模块成长：" + created.error_message)
	var result := Candidate.new()
	result.equipment = created.value
	return DomainResult.ok(result)


## 清除已复制进模块的单一类型，萤石和耀石互不清除。
## [param state] 独立装备候选视图。
## [param kind] 模块类型编号。
static func _remove_selected_growth(state: Dictionary, kind: int) -> void:
	match kind:
		1: state["processing"] = {}
		3, 4:
			var levels: Dictionary = state.extra_attributes.levels
			for key: String in levels.keys():
				if key.begins_with("fluorite:" if kind == 3 else "brilliant:"): levels.erase(key)
		5: state["strengthening"] = {}
		6: state["vehicle_sockets"] = {}
		7: state["forging"] = {}


## 保留晶石的绑定传播，不能通过模块洗掉已镶嵌晶石的绑定。
## [param memory] 单一类型的成长记忆。
## 返回任一内嵌晶石绑定时为true。
static func _has_bound_crystal(memory: EquipmentMemory) -> bool:
	for index in memory.sockets.capacity():
		if memory.sockets.slot_at(index).bound: return true
	return false
