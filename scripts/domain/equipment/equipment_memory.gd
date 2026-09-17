class_name EquipmentMemory
extends RefCounted

var source_definition_id := ""
var module_type := 0
var processing := EquipmentProcessing.new()
var extra := ExtraAttributes.new()
var strengthening := EquipmentStrengthening.new()
var sockets := VehicleSockets.new()


## 恢复模块内唯一一种成长，拒绝不完整、空载伪装和混合载荷。
## [param raw] 旧档默认空对象，新档携带来源和类型化成长边界。
## 返回独立记忆对象或错误。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary: return DomainResult.failure(&"memory.state", "记忆模块状态必须为对象")
	var result := EquipmentMemory.new()
	if raw.is_empty(): return DomainResult.ok(result)
	if raw.get("version") != 1 or not raw.get("source_definition_id") is String or String(raw.source_definition_id).is_empty() or raw.get("module_type") not in EquipmentMemoryRules.TYPES:
		return DomainResult.failure(&"memory.state", "记忆模块来源或类型无效")
	result.source_definition_id = raw.source_definition_id
	result.module_type = int(raw.module_type)
	var payload: Variant = raw.get("payload", {})
	var checked: DomainResult
	match result.module_type:
		1:
			checked = EquipmentProcessing.restore(payload)
			if checked.is_ok: result.processing = checked.value
		3, 4:
			checked = ExtraAttributes.restore(payload)
			if checked.is_ok: result.extra = checked.value
		5:
			checked = EquipmentStrengthening.restore(payload)
			if checked.is_ok: result.strengthening = checked.value
		6:
			checked = VehicleSockets.restore(payload)
			if checked.is_ok: result.sockets = checked.value
	if not checked.is_ok: return checked
	if not result.has_growth(): return DomainResult.failure(&"memory.empty_payload", "记忆模块没有可转移成长")
	if result.module_type in [3, 4]:
		var family := "fluorite:" if result.module_type == 3 else "brilliant:"
		for key: String in result.extra.to_dictionary().levels:
			if not key.begins_with(family): return DomainResult.failure(&"memory.mixed_payload", "记忆模块混入其他类型成长")
	return DomainResult.ok(result)


## 判断模块内是否真的有加工增量、星级或已开孔。
## 返回有实际成长时为true。
func has_growth() -> bool:
	match module_type:
		1: return not processing.to_dictionary().increments.is_empty()
		3, 4: return not extra.to_dictionary().levels.is_empty()
		5: return strengthening.level > 0
		6: return sockets.opened_count() > 0
	return false


## 导出该模块唯一关联的装备成长字段，供受控目录再次验证目标上限。
## 返回不含装备身份和其他成长的状态字典。
func equipment_state() -> Dictionary:
	match module_type:
		1: return {"processing": processing.to_dictionary()}
		3, 4: return {"extra_attributes": extra.to_dictionary()}
		5: return {"strengthening": strengthening.to_dictionary()}
		6: return {"vehicle_sockets": sockets.to_dictionary()}
	return {}


## 用来源装备资格验证记忆，防止将无效或越界成长装入可交易模块。
## [param expected_type] 模块物品定义允许的唯一类型。
## [param catalog] 同一受控目录。
## 返回合法记忆或具体拒绝原因。
func validate_for(expected_type: int, catalog: ItemCatalog) -> DomainResult:
	if source_definition_id.is_empty(): return DomainResult.ok()
	var profile: EquipmentMemoryRules.Profile = catalog.memory_rules.profiles.get(source_definition_id)
	if module_type != expected_type or profile == null or module_type not in profile.extract_types:
		return DomainResult.failure(&"memory.incompatible", "模块与原装备成长不兼容")
	var checked := catalog.create(source_definition_id, equipment_state())
	return DomainResult.ok() if checked.is_ok else checked


## 从装备抽取所选类型的独立快照，不修改原装备。
## [param equipment] 已由目录构造的战车装备。
## [param kind] 原版模块编号。
## 返回非空成长快照或没有可提取内容。
static func capture(equipment: VehicleEquipment, kind: int) -> DomainResult:
	var payload := {}
	match kind:
		1: payload = equipment.processing.to_dictionary()
		3, 4:
			var levels := {}
			var family := "fluorite:" if kind == 3 else "brilliant:"
			for key: String in equipment.extra_attributes.to_dictionary().levels:
				if key.begins_with(family): levels[key] = equipment.extra_attributes.level(key)
			payload = {"version": 1, "levels": levels}
		5: payload = equipment.strengthening.to_dictionary()
		6: payload = equipment.sockets.to_dictionary()
	return restore({"version": 1, "source_definition_id": equipment.definition_id, "module_type": kind, "payload": payload})


## 保存原始来源和独立成长载荷，空模块保持空对象兼容旧档。
## 返回可序列化状态。
func to_dictionary() -> Dictionary:
	if source_definition_id.is_empty(): return {}
	return {"version": 1, "source_definition_id": source_definition_id, "module_type": module_type, "payload": equipment_state().values()[0]}
