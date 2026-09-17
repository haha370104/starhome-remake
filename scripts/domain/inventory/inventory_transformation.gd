class_name InventoryTransformation
extends RefCounted


## 预检多个唯一实例替换与销毁，再一次性支付材料并提交库存。
## [param inventory] 当前库存聚合。
## [param replacements] 同身份独立候选，不允许直接传当前物品引用。
## [param removed_ids] 待销毁的唯一实例身份，不能同时被替换。
## [param requirements] 不含受影响实例定义的可堆叠材料要求。
## [param currency_cost] 非负金币费用。
## 返回完整交易摘要；所有拒绝均发生于修改前。
static func apply(inventory: Inventory, replacements: Array[GameItem], removed_ids: PackedStringArray, requirements: Array[Dictionary], currency_cost: int) -> DomainResult:
	var checked := inventory._validate_requirements(requirements)
	if not checked.is_ok: return checked
	if currency_cost < 0 or inventory.currency < currency_cost:
		return DomainResult.failure(&"inventory.transform_cost", "加工费用无效或星际币不足")
	var affected: Dictionary[String, GameItem] = {}
	for candidate: GameItem in replacements:
		if candidate == null or affected.has(candidate.instance_id):
			return DomainResult.failure(&"inventory.transform_identity", "重复或缺失加工候选")
		affected[candidate.instance_id] = candidate
	for id: String in removed_ids:
		if affected.has(id): return DomainResult.failure(&"inventory.transform_identity", "同一物品不能重复替换或销毁")
		affected[id] = null
	if affected.is_empty(): return DomainResult.failure(&"inventory.transform_identity", "缺少加工目标")
	for id: String in affected:
		var original := inventory.find(id)
		var candidate: GameItem = affected[id]
		if original == null or original.locked or original.quantity != 1 or original.max_stack != 1 or checked.value.has(original.definition_id):
			return DomainResult.failure(&"inventory.transform_target", "请卸下并解锁加工所需的唯一物品")
		if candidate != null and (candidate == original or candidate.quantity != 1 or candidate.max_stack != 1):
			return DomainResult.failure(&"inventory.transform_identity", "加工结果必须是独立的单件实例")
	var layouts: Array[Dictionary] = []
	for original: GameItem in inventory.items():
		var candidate: GameItem = affected.get(original.instance_id, original)
		if candidate != null: layouts.append(candidate.to_layout_dictionary())
	var layout_check := InventoryLayout.validate(layouts)
	if not layout_check.is_ok: return layout_check
	var consumed := inventory._consume_requirements_uncommitted(requirements)
	var final_items: Array[GameItem] = []
	for original: GameItem in inventory.items():
		var candidate: GameItem = affected.get(original.instance_id, original)
		if candidate != null: final_items.append(candidate)
	inventory._items = final_items
	inventory.currency -= currency_cost
	inventory.commit_transfer()
	return DomainResult.ok({"materials": consumed, "currency": currency_cost, "removed_ids": removed_ids.duplicate()})
