class_name CrystalSourceService
extends RefCounted

const COMMANDS := ["query_crystal_source", "grow_crystal_source", "inlay_crystal_source", "extract_crystal_source", "compose_crystal_source", "buy_crystal_source"]
const MODES := ["quality", "growth", "inlay", "extract", "compose"]
var _items: ItemCatalog
var _random := RandomNumberGenerator.new()


## 装配晶源体独立应用服务与服务器随机源。
## [param items] 权威只读目录。
func _init(items: ItemCatalog) -> void:
	_items = items
	_random.randomize()


## 在信任边界验证选择与数量，仅将类型明确的意图交给玩家事务。
## [param player] 本次事务的隔离玩家。[param command] 客户端命令。
## 返回操作摘要或拒绝；不接受客户端价格、概率、属性与结果。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var mode := String(command.get("mode", "quality"))
	if action not in COMMANDS or mode not in MODES: return _invalid()
	for key: String in ["protected", "confirmed"]:
		if not command.get(key, false) is bool: return _invalid()
	for key: String in ["instance_id", "material_id", "definition_id"]:
		if not command.get(key, "") is String: return _invalid()
	if not CrystalSourceRules.integer(command.get("index", 0), 0, 2) \
		or not CrystalSourceRules.integer(command.get("stabilizers", 0), 0, 7): return _invalid()
	var id := String(command.get("instance_id", ""))
	var material_id := String(command.get("material_id", ""))
	var index := int(command.get("index", 0))
	var stabilizers := int(command.get("stabilizers", 0))
	var protected := bool(command.get("protected", false))
	var confirmed := bool(command.get("confirmed", false))
	var revision := -1
	if action != "query_crystal_source":
		if not CrystalSourceRules.integer(command.get("inventory_revision"), 0, 9007199254740991): return _invalid()
		revision = int(command.inventory_revision)
	var result: DomainResult
	match action:
		"query_crystal_source": result = DomainResult.ok({})
		"grow_crystal_source":
			result = PlayerCrystalSourceActions.grow(player, _items, id, mode, protected, confirmed, revision, _random.randf())
		"inlay_crystal_source":
			result = PlayerCrystalSourceActions.inlay(player, _items, id, material_id, index, revision)
		"extract_crystal_source":
			result = PlayerCrystalSourceActions.extract(player, _items, id, index, confirmed, revision, new_id())
		"compose_crystal_source":
			result = PlayerCrystalSourceActions.compose(player, _items, material_id, stabilizers, revision, confirmed, new_id(), _random.randf())
		"buy_crystal_source":
			var definition_id := String(command.get("definition_id", ""))
			if not _items.crystal_source_rules.offers.has(definition_id) or not CrystalSourceRules.integer(command.get("quantity", 1), 1, 999): return _invalid()
			var product := _items.create(definition_id, {"instance_id": new_id(), "quantity": int(command.get("quantity", 1))})
			if not product.is_ok: return product
			result = PlayerWorkshopPurchases.purchase(player, product.value, _items.crystal_source_rules.offers[definition_id], revision)
	if result.is_ok:
		result.value.merge({"action": action, "instance_id": id, "material_id": material_id, "mode": mode,
			"index": index, "stabilizers": stabilizers, "protected": protected}, true)
	return result


## 从当前领域状态构建窗口投影，预演计划和装备对象不会跨网络。
## [param player] 权威玩家。[param operation] 已校验的最近选择。
## 返回晶源体专用窗口快照。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	return CrystalSourceWorkshopView.build(player, _items, operation)


## 为产物提供跨请求独立的身份，避免合成与购买快速连点冲突。
## 返回密码学随机业务身份。
static func new_id() -> String:
	return "crystal-source." + Crypto.new().generate_random_bytes(16).hex_encode()


## 构造命令边界失败，不把非法数字截断后执行。
## 返回明确的参数错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"crystal_source.command", "晶源体操作、材料或数量无效")
