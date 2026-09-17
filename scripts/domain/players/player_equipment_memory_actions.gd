class_name PlayerEquipmentMemoryActions
extends RefCounted

const STABILIZER := "equipment_memory_stabilizer"


## 预检唯一装备、模块与可选稳压剂，构造成功候选但不修改库存。
## [param player] 当前事务玩家。
## [param catalog] 权威目录。
## [param id] 背包装备实例。
## [param module_id] 唯一模块实例。
## [param mode] extract提取或transfer转移。
## [param stabilized] 是否投入一份稳压剂。
## 返回概率、费用与独立候选。
static func preview(player: Player, catalog: ItemCatalog, id: String, module_id: String, mode: String, stabilized: bool) -> DomainResult:
	var item := player.inventory.find(id) as VehicleEquipment
	var module := player.inventory.find(module_id) as EquipmentMemoryModule
	if item == null or item.locked or item.durability <= 0:
		return DomainResult.failure(&"memory.target", "请卸下并解锁战车装备，损坏装备须先维护")
	if module == null or module.locked or mode not in ["extract", "transfer"]:
		return DomainResult.failure(&"memory.module", "请选择未锁定的记忆模块与操作方式")
	var requirements: Array[Dictionary] = []
	if stabilized: requirements.append({"definition_id": STABILIZER, "quantity": 1})
	var payment := player.inventory.quote_upgrade_cost(requirements, 0)
	var candidate := EquipmentMemoryTransfer.extract(item, module, catalog, payment.bound_material) if mode == "extract" else EquipmentMemoryTransfer.transfer(item, module, catalog, payment.bound_material)
	if not candidate.is_ok: return candidate
	return DomainResult.ok({"candidate": candidate.value, "chance": catalog.memory_rules.stabilized_chance if stabilized else catalog.memory_rules.chance,
		"can_execute": payment.can_execute, "costs": payment.costs, "requirements": requirements, "currency": 0,
		"reason": "" if payment.can_execute else "未锁定的电磁稳压剂不足"})


## 原子移动一类成长，失败消费模块；目标和未选择成长始终保留。
## [param player] 当前玩家。
## [param catalog] 权威规则目录。
## [param id] 源或目标装备实例。
## [param module_id] 当前模块身份。
## [param mode] 提取或转移。
## [param stabilized] 是否使用一份稳压剂。
## [param revision] 预览时库存版本。
## [param confirmed] 是否确认模块消耗与对应成长去向。
## [param roll] 服务端随机样本。
## 返回交易摘要或无副作用的拒绝。
static func execute(player: Player, catalog: ItemCatalog, id: String, module_id: String, mode: String, stabilized: bool, revision: int, confirmed: bool, roll: float) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	if not confirmed or not is_finite(roll) or roll < 0 or roll >= 1:
		return DomainResult.failure(&"memory.confirm", "请确认提取或转移的成长去向和失败后果")
	var quote := preview(player, catalog, id, module_id, mode, stabilized)
	if not quote.is_ok: return quote
	if not quote.value.can_execute: return DomainResult.failure(&"memory.requirements", quote.value.reason)
	var success := roll < float(quote.value.chance)
	var candidate: EquipmentMemoryTransfer.Candidate = quote.value.candidate
	var replacements: Array[GameItem] = []
	var removed := PackedStringArray()
	if success:
		replacements.append(candidate.equipment)
		if mode == "extract": replacements.append(candidate.module)
	if mode == "transfer" or not success: removed.append(module_id)
	var result := InventoryTransformation.apply(player.inventory, replacements, removed, quote.value.requirements, 0)
	if not result.is_ok: return result
	result.value.merge({"success": success, "mode": mode, "message": "%s：%s" % ["成长提取" if mode == "extract" else "成长转移", "成功" if success else "失败，模块已消耗，装备保持原状"]})
	return result
