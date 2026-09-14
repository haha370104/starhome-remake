class_name AuthoritativeCommerceService
extends RefCounted

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const MerchantCatalogScript := preload("res://scripts/domain/commerce/weapon_merchant_catalog.gd")
const QuestServiceScript := preload("res://scripts/server/commerce/repeatable_quest_service.gd")
const PlayerStateMapperScript := preload("res://scripts/server/persistence/player_state_mapper.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/shared/player_panel_projector.gd"
)

const COMMAND_TYPES := [
	"query_weapon_merchant", "buy_from_weapon_merchant", "sell_to_weapon_merchant",
	"accept_weapon_merchant_task", "turn_in_weapon_merchant_task",
]

var _catalog: ItemCatalog
var _merchants: Dictionary = {}
var quests = QuestServiceScript.new()
var _mapper: PlayerStateMapper
var _projector: PlayerPanelProjector
var _next_instance_serial := 1


## 初始化统一物品、商店、任务、存档映射和面板投影依赖。
## 返回初始化后的服务或具体配置错误。
func initialize() -> DomainResult:
	_catalog = ItemCatalogScript.new()
	var items_loaded := _catalog.initialize()
	if not items_loaded.is_ok:
		return items_loaded
	_merchants.clear()
	var quests_loaded: DomainResult = quests.initialize(_catalog)
	if not quests_loaded.is_ok:
		return quests_loaded
	for merchant_id: String in quests.catalog.providers:
		var merchant = MerchantCatalogScript.new()
		var merchant_loaded: DomainResult = merchant.initialize(_catalog, merchant_id)
		if not merchant_loaded.is_ok:
			return merchant_loaded
		_merchants[merchant_id] = merchant
	_mapper = PlayerStateMapperScript.new(_catalog)
	var skill_config := JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json")
	if not skill_config.is_ok:
		return skill_config
	_projector = PlayerPanelProjectorScript.new(_catalog, skill_config.value)
	return DomainResult.ok(self)


## 判断面板命令是否属于商店/任务事务。
## [param command_type] 命令 type 字段。
## 返回本服务能否处理该命令。
static func handles(command_type: String) -> bool:
	return command_type in COMMAND_TYPES


## 执行一次由会话绑定玩家身份的权威交易或任务命令。
## [param state] 当前持久化玩家聚合。
## [param command] 不可信客户端意图。
## 返回待提交存档、操作结果和统一面板快照。
func execute(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	if state == null or _mapper == null or _projector == null:
		return DomainResult.failure(&"commerce.service_unavailable", "commerce service is unavailable")
	var mapped: DomainResult = _mapper.to_domain(state)
	if not mapped.is_ok:
		return mapped
	var player: Player = mapped.value
	var command_type := String(command.get("type", ""))
	var merchant_id := String(command.get("merchant_id", "weapon_merchant"))
	var merchant = _merchants.get(merchant_id)
	if merchant == null:
		return DomainResult.failure(&"commerce.merchant_missing", "merchant is not registered")
	var changed := command_type != "query_weapon_merchant"
	var operation := _execute_command(player, command_type, command, merchant_id, merchant)
	if not operation.is_ok:
		return operation
	if operation.value is Dictionary:
		operation.value["merchant_id"] = merchant_id
	var candidate: PlayerStateRecord = state.duplicate_record()
	if changed:
		var persisted := _mapper.to_record(player)
		if not persisted.is_ok:
			return persisted
		candidate = persisted.value
	return DomainResult.ok({
		"candidate": candidate,
		"changed": changed,
		"operation": operation.value,
		"panel_bundle": _build_bundle(player, operation.value, merchant_id),
	})


## 从已提交存档重建玩家面板和商店/任务快照。
## [param state] 仓储返回的最新 revision 状态。
## [param operation] 最近一次交易或任务操作结果。
## 返回客户端只读面板组合数据。
func build_bundle(state: PlayerStateRecord, operation: Dictionary = {}) -> Dictionary:
	var mapped: DomainResult = _mapper.to_domain(state) if state != null else DomainResult.failure(
		&"commerce.state_missing", "player state is missing"
	)
	var merchant_id := String(operation.get("merchant_id", "weapon_merchant"))
	return _build_bundle(mapped.value, operation, merchant_id) if mapped.is_ok else {}


## 把内部死亡事件应用到隔离聚合；进度由自动存档写入，领奖仍走即时事务提交。
func record_monster_kill(state: PlayerStateRecord, event: Dictionary) -> DomainResult:
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok:
		return mapped
	if not quests.record_monster_kill(mapped.value, event):
		return DomainResult.ok({"changed": false})
	var persisted := _mapper.to_record(mapped.value)
	if not persisted.is_ok:
		return persisted
	return DomainResult.ok({"changed": true, "candidate": persisted.value})


## 把已验证会话命令分派给指定商人的权威交易或普通武器商人任务。
## [param player] 当前权威玩家聚合。
## [param command_type] 客户端命令类型。
## [param command] 未可信的命令参数。
## [param merchant_id] 当前交互的商人标识。
## [param merchant] 已从服务端注册表解析的商人目录。
## 返回交易、查询或任务结果。
func _execute_command(
	player: Player,
	command_type: String,
	command: Dictionary,
	merchant_id: String,
	merchant,
) -> DomainResult:
	match command_type:
		"query_weapon_merchant":
			return DomainResult.ok({"action": "query", "merchant_id": merchant_id})
		"buy_from_weapon_merchant":
			return _buy(player, command, merchant)
		"sell_to_weapon_merchant":
			return _sell(player, command, merchant)
		"accept_weapon_merchant_task", "turn_in_weapon_merchant_task":
			return quests.execute(player, merchant_id, command)
	return DomainResult.failure(&"commerce.unknown_command", "unknown commerce command")


## 校验背包版本、商品白名单与货币后完成一次买入。
## [param player] 当前权威玩家聚合。
## [param command] 买入意图。
## [param merchant] 当前商人目录。
## 返回购买结果或明确拒绝原因。
func _buy(player: Player, command: Dictionary, merchant) -> DomainResult:
	var revision_result := player.inventory.require_revision(int(command.get("inventory_revision", -1)))
	if not revision_result.is_ok:
		return revision_result
	var definition_id := String(command.get("definition_id", ""))
	var offer: Dictionary = merchant.offer(definition_id)
	if offer.is_empty():
		return DomainResult.failure(&"commerce.item_not_offered", "merchant does not sell this item")
	var price := int(offer["price"])
	if player.inventory.currency < price:
		return DomainResult.failure(&"commerce.insufficient_currency", "not enough currency")
	var created := _catalog.create(definition_id, {
		"instance_id": _new_instance_id(definition_id), "quantity": 1,
	})
	if not created.is_ok:
		return created
	var added := player.inventory.add_reward(created.value)
	if not added.is_ok:
		return added
	player.inventory.currency -= price
	return DomainResult.ok({"action": "buy", "definition_id": definition_id, "price": price})


## 校验背包版本和物品所有权后完成一次卖出。
## [param player] 当前权威玩家聚合。
## [param command] 卖出意图。
## [param merchant] 当前商人目录，用于计算收购价。
## 返回卖出结果或明确拒绝原因。
func _sell(player: Player, command: Dictionary, merchant) -> DomainResult:
	var revision_result := player.inventory.require_revision(int(command.get("inventory_revision", -1)))
	if not revision_result.is_ok:
		return revision_result
	var instance_id := String(command.get("instance_id", ""))
	var quantity := int(command.get("quantity", 1))
	var item := player.inventory.find(instance_id)
	if item == null:
		return DomainResult.failure(&"inventory.item_not_found", "inventory item does not exist")
	var unit_price: int = merchant.purchase_price(item.definition_id)
	var removed := player.inventory.remove_quantity(instance_id, quantity)
	if not removed.is_ok:
		return removed
	player.inventory.currency += unit_price * quantity
	return DomainResult.ok({
		"action": "sell", "definition_id": item.definition_id,
		"quantity": quantity, "price": unit_price * quantity,
	})




## 构造玩家面板与当前商人共用的响应快照。
## [param player] 当前权威玩家聚合。
## [param operation] 最近一次命令结果。
## [param merchant_id] 要展示的商人标识。
## 返回客户端只读 bundle。
func _build_bundle(
	player: Player,
	operation: Dictionary = {},
	merchant_id := "weapon_merchant",
) -> Dictionary:
	var merchant = _merchants.get(merchant_id, _merchants.get("weapon_merchant"))
	if merchant == null:
		return {}
	var bundle := _projector.build_bundle(player)
	var tasks: Array[Dictionary] = quests.snapshots(player, merchant_id)
	var sell_items: Array[Dictionary] = []
	for item: GameItem in player.inventory.items():
		var view := item.to_view_dictionary()
		view["quantity"] = item.quantity
		view["unit_price"] = merchant.purchase_price(item.definition_id)
		view["presentation"] = item.presentation.duplicate(true)
		sell_items.append(view)
	bundle["commerce"] = {
		"merchant": merchant.merchant_config(),
		"offers": merchant.offers(),
		"sell_items": sell_items,
		"task": tasks[0] if not tasks.is_empty() else {},
		"tasks": tasks,
		"operation": operation.duplicate(true),
	}
	return bundle


## 生成仅在当前服务进程内唯一的新物品实例标识。
## [param definition_id] 被创建物品的定义标识。
## 返回带顺序号的实例 ID。
func _new_instance_id(definition_id: String) -> String:
	var value := "shop.%d.%s" % [_next_instance_serial, definition_id]
	_next_instance_serial += 1
	return value
