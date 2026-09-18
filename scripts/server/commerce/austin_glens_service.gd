class_name AustinGlensService
extends RefCounted

const COMMANDS := ["query_austin_glens", "change_austin_glens", "buy_austin_glens"]
var _items: ItemCatalog


## 注入独立装备服务的权威目录。
## [param items] 已加载规则与物品。
func _init(items: ItemCatalog) -> void:
	_items = items


## 校验协议边界后只执行客户端选择，成本与属性均由服务器决定。
## [param player] 隔离玩家候选。[param command] 不可信客户端意图。
## 返回操作摘要或拒绝。
func execute(player: Player, command: Dictionary) -> DomainResult:
	for key: String in ["type", "mode", "instance_id", "material_id", "definition_id"]:
		if not command.get(key, "") is String: return _invalid()
	var action := String(command.get("type", ""))
	var mode := String(command.get("mode", "color"))
	if action not in COMMANDS or mode not in AustinGlensRules.OPERATIONS or not command.get("confirmed", false) is bool \
		or not AustinGlensRules.integer(command.get("index", 0), 0, 1): return _invalid()
	var id := String(command.get("instance_id", ""))
	var material_id := String(command.get("material_id", ""))
	var index := int(command.get("index", 0))
	var revision := -1
	if action != "query_austin_glens":
		if not AustinGlensRules.integer(command.get("inventory_revision"), 0, 9007199254740991): return _invalid()
		revision = int(command.inventory_revision)
	var result: DomainResult
	match action:
		"query_austin_glens": result = DomainResult.ok({})
		"change_austin_glens": result = PlayerAustinActions.execute(player, _items, id, mode, index, material_id, revision, bool(command.get("confirmed", false)))
		"buy_austin_glens":
			var definition_id := String(command.get("definition_id", ""))
			if not _items.austin_rules.offers.has(definition_id) or not AustinGlensRules.integer(command.get("quantity", 1), 1, 99): return _invalid()
			var product := _items.create(definition_id, {"instance_id": "austin." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": int(command.get("quantity", 1))})
			if not product.is_ok: return product
			result = PlayerWorkshopPurchases.purchase(player, product.value, _items.austin_rules.offers[definition_id], revision)
	if result.is_ok: result.value.merge({"action": action, "mode": mode, "instance_id": id, "material_id": material_id, "index": index}, true)
	return result


## 输出无领域引用的专用窗口快照。
## [param player] 权威玩家。[param operation] 已核验操作。
## 返回JSON兼容投影。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	return AustinGlensWorkshopView.build(player, _items, operation)


## 拒绝类型伪造或越界参数，不进行数字截断。
## 返回参数错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"austin.command", "奥斯格兰操作、孔位或数量无效")
