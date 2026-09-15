class_name PremiumShopService
extends RefCounted

var _catalog: ItemCatalog
var _offers: Dictionary = {}


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
		if String(definition.get("attachment_family", "")) not in ["old_joint", "new_joint"] \
				or int(row.get("price", 0)) <= 0 or _offers.has(row.get("definition_id")):
			return DomainResult.failure(&"commerce.invalid_offer", "invalid premium catalog")
		var offer := PremiumShopOffer.new(row, definition)
		_offers[offer.definition_id] = offer
	return DomainResult.ok()


## 创建服务端商品实例并委托玩家聚合完成扣款和入包。
## [param player] 本次隔离事务内的权威玩家。
## [param command] 不可信的购买意图；价格、数量和余额均不从客户端读取。
## 返回购买结果或领域拒绝原因。
func purchase(player: Player, command: Dictionary) -> DomainResult:
	var offer: PremiumShopOffer = _offers.get(String(command.get("definition_id", "")))
	if offer == null:
		return DomainResult.failure(&"commerce.item_not_offered", "premium item is not offered")
	var created := _catalog.create(offer.definition_id, {
		"instance_id": "premium.%s" % Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": 1,
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
		offers.append(offer.snapshot())
	return {"offers": offers, "amethyst": player.amethyst.balance(), "operation": operation.duplicate(true)}
