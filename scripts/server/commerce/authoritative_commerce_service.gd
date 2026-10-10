class_name AuthoritativeCommerceService
extends RefCounted

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const MerchantCatalogScript := preload("res://scripts/domain/commerce/weapon_merchant_catalog.gd")
const QuestServiceScript := preload("res://scripts/server/commerce/repeatable_quest_service.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/shared/player_panel_projector.gd"
)

const COMMAND_TYPES := [
	"query_premium_shop", "buy_premium_item",
	"query_attachment_upgrades", "upgrade_attachment",
	"query_weapon_merchant", "buy_from_weapon_merchant", "sell_to_weapon_merchant",
	"accept_weapon_merchant_task", "turn_in_weapon_merchant_task", "abandon_weapon_merchant_task",
]
const TASK_COMMANDS := ["accept_weapon_merchant_task", "turn_in_weapon_merchant_task", "abandon_weapon_merchant_task"]

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
var _clothing_improvement: ClothingImprovementService
var _equipment_memory: EquipmentMemoryService
var _equipment_dismantle: EquipmentDismantleService
var _equipment_forging: EquipmentForgingService
var _crystal_source: CrystalSourceService
var _austin_glens: AustinGlensService
var _sama: SamaService
var _central: CentralService
var _catalog: ItemCatalog
var _merchants: Dictionary = {}
var quests = QuestServiceScript.new()
var _projector: PlayerPanelProjector
var _next_instance_serial := 1


## 初始化统一物品、商店、任务、存档映射和面板投影依赖。
## 返回初始化后的服务或具体配置错误。
## [param _rewards] 同一服务器共享的奖励切面，省略时使用独立默认策略。
func initialize(_rewards: RewardPipeline = null) -> DomainResult:
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
	_clothing_improvement = ClothingImprovementService.new(_catalog)
	_equipment_memory = EquipmentMemoryService.new(_catalog)
	_equipment_dismantle = EquipmentDismantleService.new(_catalog)
	_equipment_forging = EquipmentForgingService.new(_catalog)
	_crystal_source = CrystalSourceService.new(_catalog)
	_austin_glens = AustinGlensService.new(_catalog)
	_sama = SamaService.new(_catalog)
	_central = CentralService.new(_catalog)
	var daily_loaded := daily.initialize(_catalog)
	if not daily_loaded.is_ok:
		return daily_loaded
	_merchants.clear()
	var quests_loaded: DomainResult = quests.initialize(_catalog)
	if not quests_loaded.is_ok:
		return quests_loaded
	var merchant_ids: Array[String] = []
	for merchant_id: String in quests.catalog.providers:
		merchant_ids.append(merchant_id)
	for merchant_id: String in MerchantCatalogScript.CONFIG_PATHS:
		if merchant_id not in merchant_ids:
			merchant_ids.append(merchant_id)
	for merchant_id: String in merchant_ids:
		var merchant = MerchantCatalogScript.new()
		var merchant_loaded: DomainResult = merchant.initialize(_catalog, merchant_id)
		if not merchant_loaded.is_ok:
			return merchant_loaded
		_merchants[merchant_id] = merchant
	var skill_config := JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json")
	if not skill_config.is_ok:
		return skill_config
	_equipment_maintenance = EquipmentMaintenanceService.new(_catalog, skill_config.value)
	_projector = PlayerPanelProjectorScript.new(_catalog, skill_config.value)
	return DomainResult.ok(self)


## 为 LLM 提供当前商人的紧凑目录和该玩家可出售物品。
## 返回仅含交易所需字段的快照，不包含完整物品说明或资源数据。
func llm_shop_snapshot(state: Player, merchant_id: String, merchant_name := "") -> DomainResult:
	if state == null:
		return DomainResult.failure(&"commerce.player_missing", "player state is unavailable")
	var merchant = _merchants.get(merchant_id)
	if merchant == null:
		return DomainResult.failure(&"commerce.merchant_missing", "merchant is not registered")
	var offers: Array[Dictionary] = []
	for offer: Dictionary in merchant.offers():
		offers.append({
			"definition_id": String(offer.get("definition_id", "")),
			"display_name": String(offer.get("display_name", "")),
			"category": String(offer.get("category", "")),
			"required_level": int(offer.get("required_level", 0)),
			"price": int(offer.get("price", 0)),
		})
	var sellable_items: Array[Dictionary] = []
	for item: GameItem in state.inventory.items():
		if item.locked:
			continue
		var unit_price: int = merchant.purchase_price(item.definition_id)
		if unit_price <= 0:
			continue
		sellable_items.append({
			"instance_id": item.instance_id,
			"definition_id": item.definition_id,
			"display_name": item.display_name,
			"quantity": item.quantity,
			"unit_price": unit_price,
		})
	return DomainResult.ok({
		"merchant_id": merchant_id,
		"merchant_name": merchant_name if not merchant_name.is_empty() else merchant.merchant_config().get("display_name", merchant_id),
		"currency": state.inventory.currency,
		"offers": offers,
		"sellable_items": sellable_items,
	})


## 判断面板命令是否属于商店/任务事务。
## [param command_type] 命令 type 字段。
## 返回本服务能否处理该命令。
static func handles(command_type: String) -> bool:
	return command_type in COMMAND_TYPES or command_type in DailyActivityService.COMMANDS \
		or command_type in ClothingEnhancementService.COMMANDS or command_type in VehicleSocketService.COMMANDS \
		or command_type in EquipmentProcessingService.COMMANDS \
		or command_type in EquipmentMaintenanceService.COMMANDS or command_type in ExtraAttributeService.COMMANDS \
		or command_type in EquipmentStrengtheningService.COMMANDS or command_type in ArmorRefinementService.COMMANDS \
		or command_type in ClothingImprovementService.COMMANDS or command_type in EquipmentMemoryService.COMMANDS \
		or command_type in EquipmentDismantleService.COMMANDS or command_type in EquipmentForgingService.COMMANDS \
		or command_type in CrystalSourceService.COMMANDS or command_type in AustinGlensService.COMMANDS or command_type in SamaService.COMMANDS or command_type in CentralService.COMMANDS


## 执行一次由会话绑定玩家身份的权威交易或任务命令。
## [param state] 当前持久化玩家聚合。
## [param command] 不可信客户端意图。
## 返回待提交领域候选、操作结果和查询快照；变更快照在提交后生成。
func execute(state: Player, command: Dictionary) -> DomainResult:
	if state == null or _projector == null:
		return DomainResult.failure(&"commerce.service_unavailable", "commerce service is unavailable")
	var command_type := String(command.get("type", ""))
	var merchant_id := String(command.get("merchant_id", "weapon_merchant"))
	var parts: Array = PlayerTransaction.COMMERCE
	var inventory_definitions: Array[String] = []
	var inventory_instances: Array[String] = []
	if command_type.begins_with("query_"):
		parts = []
	elif command_type in ["buy_from_weapon_merchant", "sell_to_weapon_merchant"]:
		parts = ["inventory"]
		if command_type == "buy_from_weapon_merchant":
			inventory_definitions.append(String(command.get("definition_id", "")))
		else:
			inventory_instances.append(String(command.get("instance_id", "")))
	elif command_type == "buy_premium_item":
		parts = ["inventory", "wallet"]
	elif command_type in ["accept_weapon_merchant_task", "abandon_weapon_merchant_task"]:
		parts = ["quests"]
	elif command_type == "turn_in_weapon_merchant_task":
		var tasks: Array[Dictionary] = quests.catalog.tasks_for(merchant_id)
		var task_id := String(command.get("task_id", tasks[0].id if tasks.size() == 1 else ""))
		var definition: Dictionary = quests.catalog.definitions.get(task_id, {})
		var training := String(definition.get("kind", "")) == "kill_training"
		parts = ["quests", "skills", "achievements"] if training else ["inventory", "quests", "achievements"]
		if not training:
			var completion := int(state.quest_states.get(task_id, {}).get("completions", 0)) + 1
			for row: Dictionary in definition.get("requirements", []) + RepeatableQuestCatalog.rewards_at(definition, completion):
				inventory_definitions.append(String(row.definition_id))
	var mapped: DomainResult = DomainResult.ok(state) if parts.is_empty() else PlayerTransaction.prepare(
		state, parts, _catalog, inventory_definitions, inventory_instances
	)
	if not mapped.is_ok:
		return mapped
	var player: Player = mapped.value
	var merchant = _merchants.get(merchant_id)
	if merchant == null:
		return DomainResult.failure(&"commerce.merchant_missing", "merchant is not registered")
	var changed := command_type not in ["query_weapon_merchant", "query_premium_shop", "query_attachment_upgrades", "query_clothing_enhancement", "query_vehicle_sockets", "query_equipment_processing", "query_equipment_maintenance", "query_extra_attributes", "query_equipment_strengthening", "query_armor_refinement"]
	if command_type == "query_clothing_improvement": changed = false
	if command_type in ["query_equipment_memory", "query_equipment_dismantle", "query_equipment_forging"]: changed = false
	if command_type in ["query_crystal_source", "query_austin_glens", "query_sama", "query_central"]: changed = false
	var operation := _execute_command(player, command_type, command, merchant_id, merchant)
	if not operation.is_ok:
		return operation
	if operation.value is Dictionary:
		operation.value["merchant_id"] = merchant_id
	var candidate := player if changed else state
	if command_type in TASK_COMMANDS:
		return DomainResult.ok({"candidate": candidate, "changed": changed, "operation": operation.value,
			"change": _task_change(state, candidate, operation.value)})
	var result := {
		"candidate": candidate,
		"changed": changed,
		"operation": operation.value,
	}
	if not changed:
		result["panel_bundle"] = _build_bundle(player, operation.value, merchant_id)
	return DomainResult.ok(result)


## 从已提交存档重建玩家面板和商店/任务快照。
## [param state] 仓储返回的最新 revision 状态。
## [param operation] 最近一次交易或任务操作结果。
## 返回客户端只读面板组合数据。
func build_bundle(state: Player, operation: Dictionary = {}) -> Dictionary:
	if state == null: return {}
	var merchant_id := String(operation.get("merchant_id", "weapon_merchant"))
	return _build_bundle(state, operation, merchant_id)


func build_task_bundle(state: Player, operation: Dictionary) -> Dictionary:
	var merchant_id := String(operation.get("merchant_id", "weapon_merchant"))
	var tasks: Array[Dictionary] = quests.snapshots(state, merchant_id)
	return {"player_change": {}, "commerce": {"merchant": _merchants[merchant_id].merchant_config(),
		"task": tasks[0] if not tasks.is_empty() else {}, "tasks": tasks, "operation": operation.duplicate(true)}}


func _task_change(before: Player, after: Player, operation: Dictionary) -> PlayerChange:
	var change := _projector.changes(before, after)
	var task_id := String(operation.task_id)
	var row: Dictionary = quests.catalog.snapshot(after, quests.catalog.definitions[task_id], quests.current_day())
	row["category"] = 0
	PlayerChange._merge_rows(change.quests, [row], "task_id")
	var skill_reward: Dictionary = operation.get("skill_level_up", {})
	if bool(skill_reward.get("upgraded", false)):
		change.attributes_changed = true
	if before.achievements != after.achievements:
		var previous: Dictionary = before.achievements.network_snapshot().counters
		var current: Dictionary = after.achievements.network_snapshot().counters
		for key: String in current:
			if current[key] != previous.get(key, 0): change.achievements[key] = current[key]
		if before.achievements.bonuses().to_dictionary() != after.achievements.bonuses().to_dictionary():
			change.attributes_changed = true
	if change.attributes_changed and change.vehicle_stats.is_empty(): change.vehicle_stats = after.calculate_vehicle_stats()
	return change


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
	if command_type in ClothingImprovementService.COMMANDS:
		return _clothing_improvement.execute(player, command)
	if command_type in EquipmentForgingService.COMMANDS:
		return _equipment_forging.execute(player, command)
	if command_type in CentralService.COMMANDS:
		return _central.execute(player, command)
	if command_type in SamaService.COMMANDS:
		return _sama.execute(player, command)
	if command_type in AustinGlensService.COMMANDS:
		return _austin_glens.execute(player, command)
	if command_type in CrystalSourceService.COMMANDS:
		return _crystal_source.execute(player, command)
	if command_type in EquipmentDismantleService.COMMANDS:
		return _equipment_dismantle.execute(player, command)
	if command_type in EquipmentMemoryService.COMMANDS:
		return _equipment_memory.execute(player, command)
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
		"accept_weapon_merchant_task", "turn_in_weapon_merchant_task", "abandon_weapon_merchant_task":
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
## [param merchant] 当前商人目录，用于计算出售价。
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
	if unit_price <= 0:
		return DomainResult.failure(&"commerce.item_not_sellable", "item has no confirmed merchant sale price")
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
	if String(operation.get("action", "")) in ClothingImprovementService.COMMANDS:
		bundle["clothing_improvement"] = _clothing_improvement.snapshot(player, operation)
	if String(operation.get("action", "")) in EquipmentMemoryService.COMMANDS:
		bundle["equipment_memory"] = _equipment_memory.snapshot(player, operation)
	if String(operation.get("action", "")) in EquipmentForgingService.COMMANDS:
		bundle["equipment_forging"] = _equipment_forging.snapshot(player, operation)
	if String(operation.get("action", "")) in CentralService.COMMANDS:
		bundle["central_workshop"] = _central.snapshot(player, operation)
	if String(operation.get("action", "")) in SamaService.COMMANDS:
		bundle["sama"] = _sama.snapshot(player, operation)
	if String(operation.get("action", "")) in AustinGlensService.COMMANDS:
		bundle["austin_glens"] = _austin_glens.snapshot(player, operation)
	if String(operation.get("action", "")) in CrystalSourceService.COMMANDS:
		bundle["crystal_source"] = _crystal_source.snapshot(player, operation)
	if String(operation.get("action", "")) in EquipmentDismantleService.COMMANDS:
		bundle["equipment_dismantle"] = _equipment_dismantle.snapshot(player, operation)
	if String(operation.get("action", "")) in EquipmentStrengtheningService.COMMANDS:
		bundle["equipment_strengthening"] = _equipment_strengthening.snapshot(player, operation)
	bundle["daily_activities"] = daily.snapshot(player)
	var tasks: Array[Dictionary] = quests.snapshots(player, merchant_id)
	var commerce := {
		"merchant": merchant.merchant_config(),
		"offers": merchant.offers(),
		"task": tasks[0] if not tasks.is_empty() else {},
		"tasks": tasks,
		"operation": operation.duplicate(true),
	}
	if String(operation.get("action", "")) == "query":
		commerce["sell_prices"] = merchant.sell_prices()
	bundle["commerce"] = commerce
	return bundle


## 生成仅在当前服务进程内唯一的新物品实例标识。
## [param definition_id] 被创建物品的定义标识。
## 返回带顺序号的实例 ID。
func _new_instance_id(definition_id: String) -> String:
	var value := "shop.%d.%s" % [_next_instance_serial, definition_id]
	_next_instance_serial += 1
	return value
