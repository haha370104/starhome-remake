class_name PremiumShopService
extends RefCounted

var _catalog: ItemCatalog
var _offers: Dictionary = {}
var _upgrade_pricing := preload("res://scripts/domain/commerce/attachment_upgrade_pricing.gd").new()


## 将初始化后相同的材料方案提供给强化服务。
## 返回权威定价领域目录。
func upgrade_pricing() -> AttachmentUpgradePricing:
	return _upgrade_pricing


## 加载服务端白名单，拒绝无效物品、重复商品和非正售价。
## [param catalog] 统一物品目录。
## 返回目录加载结果。
func initialize(catalog: ItemCatalog) -> DomainResult:
	_catalog = catalog
	_offers.clear()
	var loaded := JsonConfigLoader.load_dictionary("res://data/gameplay/commerce/premium_shop_v1.json")
	if not loaded.is_ok:
		return loaded
	for row: Dictionary in loaded.value.get("offers", []):
		var definition := catalog.definition(String(row.get("definition_id", "")))
		var is_material: bool = definition.get("kind", "") == "material" and definition.get("premium_category", "") == "upgrade_material"
		if (String(definition.get("attachment_family", "")) not in ["old_joint", "new_joint"] and not is_material) \
				or int(row.get("price", 0)) <= 0 or _offers.has(row.get("definition_id")):
			return DomainResult.failure(&"commerce.invalid_offer", "invalid premium catalog")
		var offer := PremiumShopOffer.new(row, definition)
		_offers[offer.definition_id] = offer
	return _upgrade_pricing.initialize(catalog, _offers)


## 创建服务端商品实例并委托玩家聚合完成扣款和入包。
## [param player] 本次隔离事务内的权威玩家。
## [param command] 不可信的购买意图；价格、数量和余额均不从客户端读取。
## 返回购买结果或领域拒绝原因。
func purchase(player: Player, command: Dictionary) -> DomainResult:
	var offer: PremiumShopOffer = _offers.get(String(command.get("definition_id", "")))
	if offer == null:
		return DomainResult.failure(&"commerce.item_not_offered", "premium item is not offered")
	var quote := offer.quote(command.get("quantity", 1) if offer.family == "upgrade_material" else 1)
	if not quote.is_ok:
		return quote
	var created := _catalog.create(offer.definition_id, {
		"instance_id": "premium.%s" % Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": quote.value.quantity,
	})
	if not created.is_ok:
		return created
	return player.purchase_premium_item(offer, created.value, int(command.get("inventory_revision", -1)))


## 查询商城快照，余额始终来自玩家钱包。
## [param player] 权威玩家。
## [param operation] 最近一次购买或查询结果。
## 返回只读商品列表和余额。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var offers: Array[Dictionary] = []
	for offer: PremiumShopOffer in _offers.values():
		var row := offer.snapshot()
		row["upgrade_plans"] = _upgrade_pricing.plans_for(offer.definition_id)
		offers.append(row)
	return {"offers": offers, "amethyst": player.amethyst.balance(), "operation": operation.duplicate(true)}
