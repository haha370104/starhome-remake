class_name PlayerArmorRefinementActions
extends RefCounted


## 核验护甲和材料，预先构造下一阶候选并检查全部成长可被保留。
## [param player] 事务内玩家聚合。
## [param items] 受控物品目录。
## [param id] 背包护甲实例。
## [param material_id] 背包精工材料实例。
## [param quantity] 投入数量。
## 返回候选装备、概率和完整费用；不修改当前玩家。
static func preview(player: Player, items: ItemCatalog, id: String, material_id: String, quantity: int) -> DomainResult:
	var armor := player.inventory.find(id) as VehicleEquipment
	var material := player.inventory.find(material_id) as ArmorRefinementMaterial
	if armor == null or armor.locked or armor.durability <= 0:
		return DomainResult.failure(&"armor_refinement.target", "请卸下并解锁护甲，损坏护甲须先维护")
	if material == null or material.locked:
		return DomainResult.failure(&"armor_refinement.material", "请选择未锁定的精工芯片或精工石")
	var quote := items.armor_refinement_rules.preview(armor.armor_refinement_profile, material, quantity)
	if not quote.is_ok: return quote
	var payment := player.inventory.quote_upgrade_cost(quote.value.requirements, quote.value.currency)
	var blank := items.create(quote.value.next_definition_id, {"instance_id": id})
	if not blank.is_ok: return blank
	var state := ArmorRefinement.replacement_state(armor, blank.value, payment.bound_material or armor.armor_refinement_profile.gift_bound)
	if not state.is_ok: return state
	var candidate := items.create(quote.value.next_definition_id, state.value)
	if not candidate.is_ok: return DomainResult.failure(&"armor_refinement.growth", "下一阶无法完整保留当前装备成长：" + candidate.error_message)
	quote.value.merge(payment)
	quote.value["candidate"] = candidate.value
	quote.value["reason"] = "" if payment.can_execute else "护甲精工材料或星际币不足"
	return quote


## 执行经确认的护甲精工，成功替换同一实例，失败原子销毁护甲和消耗材料。
## [param player] 玩家聚合。
## [param items] 权威目录。
## [param id] 护甲实例。
## [param material_id] 精工材料实例。
## [param quantity] 投入数量。
## [param revision] 确认时库存版本。
## [param destruction_confirmed] 是否明确确认失败销毁护甲及其中晶石。
## [param roll] 权威随机样本。
## 返回完整操作摘要，拒绝时不改变物品或余额。
static func execute(player: Player, items: ItemCatalog, id: String, material_id: String, quantity: int, revision: int, destruction_confirmed: bool, roll: float) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	if not destruction_confirmed or not is_finite(roll) or roll < 0 or roll >= 1:
		return DomainResult.failure(&"armor_refinement.confirm", "请确认失败会销毁护甲和其中晶石")
	var quote := preview(player, items, id, material_id, quantity)
	if not quote.is_ok: return quote
	if not quote.value.can_execute:
		return DomainResult.failure(&"armor_refinement.requirements", quote.value.reason)
	var old := player.inventory.find(id)
	var success := roll < float(quote.value.chance)
	var replacement: VehicleEquipment = quote.value.candidate if success else null
	var settled := player.inventory.transform_item(id, replacement, quote.value.requirements, quote.value.currency)
	if not settled.is_ok: return settled
	settled.value.merge({"success": success, "instance_id": id, "before_definition_id": old.definition_id,
		"after_definition_id": replacement.definition_id if success else "",
		"message": "%s：%s" % [old.display_name, "精工成功，已有晶石保留" if success else "精工失败，护甲与其中晶石已销毁，材料已消耗"]})
	return settled
