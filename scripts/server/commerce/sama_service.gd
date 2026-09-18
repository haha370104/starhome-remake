class_name SamaService
extends RefCounted

const COMMANDS := ["query_sama", "change_sama", "buy_sama"]
var _items: ItemCatalog


## 注入权威物品和成长规则目录。
## [param items] 已加载目录。
func _init(items: ItemCatalog) -> void:
	_items = items


## 校验不可信意图；颜色、成本和变化结果只能从服务器商品与规则产生。
## [param player] 隔离候选玩家。[param command] 客户端命令。
## 返回操作摘要或协议/领域拒绝。
func execute(player: Player, command: Dictionary) -> DomainResult:
	for key: String in ["type", "mode", "instance_id", "material_id", "definition_id"]:
		if not command.get(key, "") is String: return _invalid()
	var action := String(command.get("type", ""))
	var mode := String(command.get("mode", "growth"))
	if action not in COMMANDS or mode not in SamaRules.OPERATIONS or not command.get("confirmed", false) is bool: return _invalid()
	var id := String(command.get("instance_id", ""))
	var donor_id := String(command.get("material_id", ""))
	var revision := -1
	if action != "query_sama":
		if not SamaRules.integer(command.get("inventory_revision"), 0, 9007199254740991): return _invalid()
		revision = int(command.inventory_revision)
	var result: DomainResult
	match action:
		"query_sama": result = DomainResult.ok({})
		"change_sama": result = PlayerSamaActions.execute(player, _items, id, mode, donor_id, revision, bool(command.get("confirmed", false)))
		"buy_sama":
			var offer: SamaRules.Offer = _items.sama_rules.offers.get(String(command.get("definition_id", "")))
			if offer == null or not SamaRules.integer(command.get("quantity", 1), 1, 999): return _invalid()
			var growth := SamaGrowth.new()
			growth.color = offer.color
			var product := _items.create(offer.definition_id, {"instance_id": "sama." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": int(command.get("quantity", 1)), "sama": growth.to_dictionary()})
			if not product.is_ok: return product
			result = PlayerWorkshopPurchases.purchase(player, product.value, offer.unit_price, revision)
	if result.is_ok: result.value.merge({"action": action, "mode": mode, "instance_id": id, "material_id": donor_id}, true)
	return result


## 输出与领域实例脱离的专用快照。
## [param player] 玩家。[param operation] 当前操作选择。
## 返回JSON兼容视图。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	return SamaWorkshopView.build(player, _items, operation)


## 统一拒绝无效命令类型或参数。
## 返回明确参数错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"sama.command", "撒玛操作、商品或数量无效")
