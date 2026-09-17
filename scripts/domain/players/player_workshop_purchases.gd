class_name PlayerWorkshopPurchases
extends RefCounted


## 购买加工材料，先检查资金与容量，成功入包后扣金币。
## [param player] 当前玩家聚合。
## [param product] 权威目录创建的商品堆叠。
## [param unit_price] 权威商售配置单价。
## [param expected_revision] 确认时背包版本。
## 返回购买结果或原子失败。
static func purchase(player: Player, product: GameItem, unit_price: int, expected_revision: int) -> DomainResult:
	var checked := player.inventory.require_revision(expected_revision)
	if not checked.is_ok:
		return checked
	if product == null or unit_price <= 0 or product.quantity < 1 or product.quantity > mini(9999, product.max_stack):
		return DomainResult.failure(&"sockets.offer_invalid", "加工材料购买数量无效")
	var total := unit_price * product.quantity
	if player.inventory.currency < total:
		return DomainResult.failure(&"sockets.currency", "星际币不足")
	var added := player.inventory.add_reward(product)
	if not added.is_ok:
		return added
	player.inventory.currency -= total
	return DomainResult.ok({"message": "已购买 %s ×%d" % [product.display_name, product.quantity], "price": total})
