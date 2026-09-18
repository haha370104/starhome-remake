class_name PlayerSamaActions
extends RefCounted


## 为自有装备建立独立成长或转移候选，原物品与钱包保持不变。
## [param player] 玩家聚合。[param catalog] 目录。[param id] 目标身份。
## [param mode] 操作。[param donor_id] 转移时被销毁的来源身份。
## 返回候选、材料和紫晶报价。
static func quote(player: Player, catalog: ItemCatalog, id: String, mode: String, donor_id: String) -> DomainResult:
	var item := player.inventory.find(id) as VehicleEquipment
	if not _eligible(item): return DomainResult.failure(&"sama.target", "请选择背包内未锁定且完好的撒玛装备；已装配的须先卸下")
	var growth: SamaGrowth = SamaGrowth.restore(item.sama.to_dictionary()).value
	var requirements: Array[Dictionary] = []
	var removed := PackedStringArray()
	var amethyst := 0
	var donor: VehicleEquipment
	if mode == "transfer":
		donor = player.inventory.find(donor_id) as VehicleEquipment
		if donor == item or not _eligible(donor): return DomainResult.failure(&"sama.donor", "请选择另一件未锁定且完好的撒玛装备作为转出来源")
		var received := growth.receive(donor.sama)
		if not received.is_ok: return received
		removed.append(donor.instance_id)
		amethyst = catalog.sama_rules.transfer_amethyst
	else:
		var advanced := growth.advance(mode, catalog.sama_rules)
		if not advanced.is_ok: return advanced
		requirements.assign(advanced.value)
	var payment := player.inventory.quote_upgrade_cost(requirements, 0)
	var state := item.to_view_dictionary()
	state.sama = growth.to_dictionary()
	state.bound = item.bound or bool(payment.bound_material) or (donor != null and donor.bound)
	var candidate := catalog.create(item.definition_id, state)
	if not candidate.is_ok: return candidate
	return DomainResult.ok({"candidate": candidate.value, "requirements": requirements, "costs": payment.costs,
		"can_execute": payment.can_execute and (amethyst == 0 or player.amethyst.can_spend(amethyst).is_ok), "amethyst": amethyst,
		"removed_ids": removed, "before": item.sama.to_dictionary(), "after": growth.to_dictionary(),
		"donor_name": donor.display_name if donor != null else ""})


## 在同一聚合事务内支付材料或紫晶并替换目标，转移成功时销毁来源。
## [param player] 玩家。[param catalog] 目录。[param id] 保留身份的目标。
## [param mode] 操作。[param donor_id] 来源。[param revision] 预览背包版本。[param confirmed] 消耗及销毁确认。
## 返回成功摘要或完全无副作用的拒绝。
static func execute(player: Player, catalog: ItemCatalog, id: String, mode: String, donor_id: String, revision: int, confirmed: bool) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	if not confirmed: return DomainResult.failure(&"sama.confirm", "请确认消耗；转移将销毁来源装备并覆盖目标的阶段与品质")
	var preview := quote(player, catalog, id, mode, donor_id)
	if not preview.is_ok: return preview
	if int(preview.value.amethyst) > 0:
		checked = player.amethyst.can_spend(int(preview.value.amethyst))
		if not checked.is_ok: return checked
	var replacements: Array[GameItem] = [preview.value.candidate]
	var paid := InventoryTransformation.apply(player.inventory, replacements, preview.value.removed_ids, preview.value.requirements, 0)
	if not paid.is_ok: return paid
	# 同步聚合内已预检钱包，没有异步操作或可失败步骤插入这两次提交之间。
	if int(preview.value.amethyst) > 0: player.amethyst.spend(int(preview.value.amethyst))
	return DomainResult.ok({"message": "撒玛%s完成" % {"growth": "阶段成长", "quality": "品质提升", "transfer": "成长转移"}[mode]})


## 检查此系列加工所需的装备自身条件。
## [param item] 背包查询结果。
## 返回是否可作为目标或来源。
static func _eligible(item: VehicleEquipment) -> bool:
	return item != null and item.sama_profile != null and not item.locked and item.durability > 0
