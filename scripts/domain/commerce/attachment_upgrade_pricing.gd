class_name AttachmentUpgradePricing
extends RefCounted

var _plans: Dictionary = {}


## 将升级材料方案与真实商城单价联结，拒绝缺料、重复阶段和超出用户预算的配置。
## [param items] 权威物品目录。
## [param offers] 以物品ID索引的领域商品。
## 返回加载成功或定价配置错误；本对象只负责材料方案，不执行强化。
func initialize(items: ItemCatalog, offers: Dictionary) -> DomainResult:
	_plans.clear()
	var loaded := JsonConfigLoader.load_dictionary("res://data/gameplay/commerce/attachment_upgrade_costs_v1.json")
	if not loaded.is_ok:
		return loaded
	for rule: Dictionary in loaded.value.rules:
		var definition := items.definition(String(rule.attachment_id))
		var family := String(definition.get("attachment_family", ""))
		var level := int(rule.current_level)
		if family not in ["old_joint", "new_joint"] or level != rule.current_level or level < 0 \
				or level >= (5 if family == "new_joint" else 4) or int(rule.target_level) != level + 1:
			return _invalid()
		var cost := 0
		var materials: Array[Dictionary] = []
		for row: Dictionary in rule.premium_materials:
			var offer: PremiumShopOffer = offers.get(String(row.definition_id))
			if offer == null or offer.family != "upgrade_material":
				return _invalid()
			var quote := offer.quote(row.quantity)
			if not quote.is_ok:
				return _invalid()
			cost += int(quote.value.price)
			materials.append({"definition_id": row.definition_id, "display_name": offer.display_name,
				"quantity": int(quote.value.quantity), "unit_price": offer.price})
		for row: Dictionary in rule.normal_materials:
			if items.definition(String(row.definition_id)).is_empty() or int(row.quantity) <= 0:
				return _invalid()
		var tier := maxi(level, 1)
		if materials.is_empty() or cost < tier * 1000 or cost > tier * 2000 or cost != tier * int(rule.coefficient):
			return _invalid()
		if not _plans.has(rule.attachment_id):
			_plans[rule.attachment_id] = []
		for previous: Dictionary in _plans[rule.attachment_id]:
			if int(previous.current_level) == level:
				return _invalid()
		_plans[rule.attachment_id].append({"current_level": level, "target_level": level + 1,
			"premium_cost": cost, "premium_materials": materials, "normal_materials": rule.normal_materials.duplicate(true),
			"currency": int(rule.currency)})
	for offer: PremiumShopOffer in offers.values():
		if offer.family in ["old_joint", "new_joint"] and plans_for(offer.definition_id).size() != (5 if offer.family == "new_joint" else 4):
			return _invalid()
	return DomainResult.ok()


## 查询某种接合器各阶段的购买材料与总价，返回独立投影。
## [param definition_id] 装置定义ID。
## 返回升级阶段方案；非接合器为空数组。
func plans_for(definition_id: String) -> Array:
	return (_plans.get(definition_id, []) as Array).duplicate(true)


## 为指定装备阶段提供唯一领域规则；满级或未开放的赠品不产生配方。
## [param definition_id] 接合器定义ID。
## [param current_level] 实例当前强化等级。
## 返回匹配规则，未配置时为空。
func plan_for(definition_id: String, current_level: int) -> AttachmentUpgradePlan:
	for row: Dictionary in _plans.get(definition_id, []):
		if int(row.current_level) == current_level:
			return AttachmentUpgradePlan.new(definition_id, row)
	return null


## 统一返回定价配置失败，不发布违反预算约束的商品方案。
## 返回领域错误。
func _invalid() -> DomainResult:
	return DomainResult.failure(&"commerce.upgrade_prices_invalid", "接合器升级材料或价格配置无效")
