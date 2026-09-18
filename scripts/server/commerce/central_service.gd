class_name CentralService
extends RefCounted

const COMMANDS := ["query_central", "change_central", "buy_central"]
var _items: ItemCatalog


## 注入权威目录。
## [param items] 已加载的中枢规则与物品定义。
func _init(items: ItemCatalog) -> void:
	_items = items


## 校验意图并执行领域事务，客户端不能指定价格、芯片类别或最终等级。
## [param player] 独立候选玩家。[param command] 外部意图。
## 返回操作结果或协议拒绝。
func execute(player: Player, command: Dictionary) -> DomainResult:
	for key: String in ["type", "instance_id", "definition_id"]:
		if not command.get(key, "") is String: return _invalid()
	var action := String(command.get("type", ""))
	if action not in COMMANDS or not command.get("confirmed", false) is bool: return _invalid()
	var revision := -1
	if action != "query_central":
		if not CentralRules.integer(command.get("inventory_revision"), 0, 9007199254740991): return _invalid()
		revision = int(command.inventory_revision)
	var id := String(command.get("instance_id", ""))
	var result: DomainResult
	match action:
		"query_central": result = DomainResult.ok({})
		"change_central": result = PlayerCentralActions.execute(player, _items, id, revision, bool(command.get("confirmed", false)))
		"buy_central":
			var definition_id := String(command.get("definition_id", ""))
			if not _items.central_rules.offers.has(definition_id): return _invalid()
			var maximum := int(_items.definition(definition_id).get("max_stack", 1))
			if not CentralRules.integer(command.get("quantity", 1), 1, maximum): return _invalid()
			var created := _items.create(definition_id, {"instance_id":"central." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity":int(command.get("quantity", 1))})
			if not created.is_ok: return created
			result = PlayerWorkshopPurchases.purchase(player, created.value, _items.central_rules.offers[definition_id], revision)
	if result.is_ok: result.value.merge({"action":action, "instance_id":id}, true)
	return result


## 生成独立工坊视图，不覆盖快照中的角色永久中枢事实。
## [param player] 玩家。[param operation] 选择与结果。
## 返回工坊数据。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	return CentralWorkshopView.build(player, _items, operation)


## 构造无效请求结果。
## 返回协议错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"central.command", "中枢操作、商品或数量无效")
