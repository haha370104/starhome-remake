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
	"query_premium_shop", "buy_premium_item",
	"query_attachment_upgrades", "upgrade_attachment",
	"query_weapon_merchant", "buy_from_weapon_merchant", "sell_to_weapon_merchant",
	"accept_weapon_merchant_task", "turn_in_weapon_merchant_task",
]

var daily := DailyActivityService.new()
var _premium := PremiumShopService.new()
var _upgrades: AttachmentUpgradeService
var _clothing_enhancements: ClothingEnhancementService
var _vehicle_sockets: VehicleSocketService
var _equipment_processing: EquipmentProcessingService
var _equipment_maintenance: EquipmentMaintenanceService
var _extra_attributes: ExtraAttributeService
var _equipment_strengthening: EquipmentStrengtheningService
var _armor_refinement: ArmorRefinementService
var _catalog: ItemCatalog
var _merchants: Dictionary = {}
var quests = QuestServiceScript.new()
var _mapper: PlayerStateMapper
var _projector: PlayerPanelProjector
var _next_instance_serial := 1


## 初始化统一物品、商店、任务、存档映射和面板投影依赖。
## 返回初始化后的服务或具体配置错误。
## [param rewards] 同一服务器共享的奖励切面，省略时使用独立默认策略。
func initialize(rewards: RewardPipeline = null) -> DomainResult:
	_catalog = ItemCatalogScript.new()
	var items_loaded := _catalog.initialize()
	if not items_loaded.is_ok:
		return items_loaded
	var premium_loaded := _premium.initialize(_catalog)
	if not premium_loaded.is_ok:
		return premium_loaded
	_upgrades = AttachmentUpgradeService.new(_premium.upgrade_pricing(), _catalog)
	_clothing_enhancements = ClothingEnhancementService.new(_catalog)
	_vehicle_sockets = VehicleSocketService.new(_catalog)
	_equipment_processing = EquipmentProcessingService.new(_catalog)
	_extra_attributes = ExtraAttributeService.new(_catalog)
	_equipment_strengthening = EquipmentStrengtheningService.new(_catalog)
	_armor_refinement = ArmorRefinementService.new(_catalog)
	var daily_loaded := daily.initialize(_catalog)
	if not daily_loaded.is_ok:
		return daily_loaded
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
	_mapper = PlayerStateMapperScript.new(_catalog, rewards)
	var skill_config := JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json")
	if not skill_config.is_ok:
		return skill_config
	_equipment_maintenance = EquipmentMaintenanceService.new(_catalog, skill_config.value)
	_projector = PlayerPanelProjectorScript.new(_catalog, skill_config.value)
	return DomainResult.ok(self)


## 判断面板命令是否属于商店/任务事务。
## [param command_type] 命令 type 字段。
## 返回本服务能否处理该命令。
static func handles(command_type: String) -> bool:
	return command_type in COMMAND_TYPES or command_type in DailyActivityService.COMMANDS \
		or command_type in ClothingEnhancementService.COMMANDS or command_type in VehicleSocketService.COMMANDS \
		or command_type in EquipmentProcessingService.COMMANDS \
		or command_type in EquipmentMaintenanceService.COMMANDS or command_type in ExtraAttributeService.COMMANDS \
		or command_type in EquipmentStrengtheningService.COMMANDS or command_type in ArmorRefinementService.COMMANDS


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
	var changed := command_type not in ["query_weapon_merchant", "query_premium_shop", "query_attachment_upgrades", "query_clothing_enhancement", "query_vehicle_sockets", "query_equipment_processing", "query_equipment_maintenance", "query_extra_attributes", "query_equipment_strengthening", "query_armor_refinement"]
	var operation := _execute_command(player, command_type, command, merchant_id, merchant)
	if not operation.is_ok:
		return operation
	if command_type == "query_daily_activities":
		changed = state.daily_activities != player.daily_activities.to_dictionary()
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
## [param state] 当前已提交的玩家存档。
## [param event] 服务端确认的怪物死亡事件。
## 返回：包含进度变更及候选存档的领域结果。
func record_monster_kill(state: PlayerStateRecord, event: Dictionary) -> DomainResult:
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok:
		return mapped
	var player: Player = mapped.value
	if String(event.get("killer_id", "")) != player.entity_id:
		return DomainResult.ok({"changed": false})
	var before := player.achievements.bonuses().to_dictionary()
	var quest_changed := quests.record_monster_kill(player, event)
	var daily_changed := daily.record_kill(player, event)
	var achievement_changed := player.record_achievement(AchievementEvent.new(
		AchievementEvent.Kind.MONSTER_KILLED, String(event.get("species_id", "")),
		1, String(event.get("death_id", ""))))
	if not quest_changed and not achievement_changed and not daily_changed:
		return DomainResult.ok({"changed": false})
	var persisted := _mapper.to_record(mapped.value)
	if not persisted.is_ok:
		return persisted
	return DomainResult.ok({"changed": true, "candidate": persisted.value,
		"title_changed": before != player.achievements.bonuses().to_dictionary()})


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
	if command_type in DailyActivityService.COMMANDS:
		return daily.execute(player, command)
	if command_type in ClothingEnhancementService.COMMANDS:
		return _clothing_enhancements.execute(player, command)
	if command_type in VehicleSocketService.COMMANDS:
		return _vehicle_sockets.execute(player, command)
	if command_type in EquipmentProcessingService.COMMANDS:
		return _equipment_processing.execute(player, command)
	if command_type in EquipmentMaintenanceService.COMMANDS:
		return _equipment_maintenance.execute(player, command)
	if command_type in ExtraAttributeService.COMMANDS:
		return _extra_attributes.execute(player, command)
	if command_type in ArmorRefinementService.COMMANDS:
		return _armor_refinement.execute(player, command)
	if command_type in EquipmentStrengtheningService.COMMANDS:
		return _equipment_strengthening.execute(player, command)
	match command_type:
		"query_attachment_upgrades":
			return DomainResult.ok({"action": "attachment_upgrade_query"})
		"upgrade_attachment":
			return _upgrades.execute(player, command)
		"query_premium_shop":
			return DomainResult.ok({"action": "premium_query"})
		"buy_premium_item":
			return _premium.purchase(player, command)
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
	bundle["premium_shop"] = _premium.snapshot(player, operation)
	bundle["attachment_upgrades"] = _upgrades.snapshot(player, operation)
	if String(operation.get("action", "")) in ClothingEnhancementService.COMMANDS:
		bundle["clothing_enhancement"] = _clothing_enhancements.snapshot(player, operation)
	if String(operation.get("action", "")) in VehicleSocketService.COMMANDS:
		bundle["vehicle_sockets"] = _vehicle_sockets.snapshot(player, operation)
	if String(operation.get("action", "")) in EquipmentProcessingService.COMMANDS:
		bundle["equipment_processing"] = _equipment_processing.snapshot(player, operation)
	if String(operation.get("action", "")) in EquipmentMaintenanceService.COMMANDS:
		bundle["equipment_maintenance"] = _equipment_maintenance.snapshot(player, operation)
	if String(operation.get("action", "")) in ExtraAttributeService.COMMANDS:
		bundle["extra_attributes"] = _extra_attributes.snapshot(player, operation)
	if String(operation.get("action", "")) in ArmorRefinementService.COMMANDS:
		bundle["armor_refinement"] = _armor_refinement.snapshot(player, operation)
	if String(operation.get("action", "")) in EquipmentStrengtheningService.COMMANDS:
		bundle["equipment_strengthening"] = _equipment_strengthening.snapshot(player, operation)
	bundle["daily_activities"] = daily.snapshot(player)
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
