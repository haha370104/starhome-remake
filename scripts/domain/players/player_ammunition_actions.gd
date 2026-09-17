class_name PlayerAmmunitionActions
extends RefCounted


## 按实际弹仓缺口报价，背包及装配中的弹药装备都可在维护地点补充。
## [param player] 同事务玩家。
## [param id] 装备实例。
## [param rules] 服务端维护地点名单。
## 返回可执行报价或明确的资格错误。
static func preview(player: Player, id: String, rules: EquipmentMaintenanceRules) -> DomainResult:
	if player.map_id not in rules.maintenance_maps:
		return DomainResult.failure(&"ammunition.location", "请返回基地或生产区补弹")
	var item := player.attachment_item(id) as Equipment
	if item == null or item.ammunition_capacity() <= 0:
		return DomainResult.failure(&"ammunition.unsupported", "请选择有弹仓的装备")
	if item.locked:
		return DomainResult.failure(&"ammunition.locked", "请先解锁装备")
	var missing := item.ammunition_capacity() - item.magazine.remaining
	if missing <= 0:
		return DomainResult.failure(&"ammunition.full", "弹仓已满")
	var price := int(item.stat("ammunition_unit_price", 0))
	if price <= 0:
		return DomainResult.failure(&"ammunition.unsupported", "尚未确认该装备补弹价格")
	var total := missing * price
	return DomainResult.ok({"can_execute": player.inventory.currency >= total, "currency": total,
		"text": "弹药：%d → %d\n补充：%d 发\n单价：%d 星际币/发\n合计：%d 星际币%s" % [item.magazine.remaining,
			item.ammunition_capacity(), missing, price, total, "\n星际币不足" if player.inventory.currency < total else ""]})


## 在同一库存版本内先校验后扣费，服务端补弹不会影响冷却、耐久或其他成长。
## [param player] 隔离玩家聚合。
## [param id] 装备实例。
## [param revision] 用户确认的库存版本。
## [param rules] 补弹地点规则。
## 返回交易结果或不改变状态的失败。
static func refill(player: Player, id: String, revision: int, rules: EquipmentMaintenanceRules) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	var quote := preview(player, id, rules)
	if not quote.is_ok: return quote
	var paid := player.inventory.pay_upgrade_cost([], quote.value.currency)
	if not paid.is_ok: return paid
	var item := player.attachment_item(id) as Equipment
	item.magazine.refill(item.ammunition_capacity())
	return DomainResult.ok({"message": "已补满弹药", "currency": quote.value.currency})
