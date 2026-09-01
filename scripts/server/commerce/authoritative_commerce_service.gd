class_name AuthoritativeCommerceService
extends RefCounted

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const MerchantCatalogScript := preload("res://scripts/domain/commerce/weapon_merchant_catalog.gd")
const TaskScript := preload("res://scripts/domain/quests/repeatable_collection_task.gd")
const PlayerStateMapperScript := preload("res://scripts/server/persistence/player_state_mapper.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/server/player_panels/player_panel_projector.gd"
)

const COMMAND_TYPES := [
	"query_weapon_merchant", "buy_from_weapon_merchant", "sell_to_weapon_merchant",
	"accept_weapon_merchant_task", "turn_in_weapon_merchant_task",
]

var _catalog: ItemCatalog
var _merchant
var _task
var _mapper: PlayerStateMapper
var _projector: PlayerPanelProjector
var _task_id := ""
var _next_instance_serial := 1


## 初始化统一物品、商店、任务、存档映射和面板投影依赖。
func initialize() -> DomainResult:
	_catalog = ItemCatalogScript.new()
	var items_loaded := _catalog.initialize()
	if not items_loaded.is_ok:
		return items_loaded
	_merchant = MerchantCatalogScript.new()
	var merchant_loaded: DomainResult = _merchant.initialize(_catalog)
	if not merchant_loaded.is_ok:
		return merchant_loaded
	var task_definition: Dictionary = _merchant.config().get("repeatable_task", {})
	_task_id = String(task_definition.get("id", ""))
	if _task_id.is_empty():
		return DomainResult.failure(&"commerce.invalid_config", "task identity is missing")
	_task = TaskScript.new(task_definition)
	_mapper = PlayerStateMapperScript.new(_catalog)
	var skill_config := JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json")
	if not skill_config.is_ok:
		return skill_config
	_projector = PlayerPanelProjectorScript.new(_catalog, skill_config.value)
	return DomainResult.ok(self)


## 判断面板命令是否属于商店/任务事务。
## [param command_type] 命令 type 字段。
static func handles(command_type: String) -> bool:
	return command_type in COMMAND_TYPES


## 执行一次由会话绑定玩家身份的权威交易或任务命令。
## [param state] 当前持久化玩家聚合。
## [param command] 不可信客户端意图。
func execute(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	if state == null or _mapper == null or _projector == null:
		return DomainResult.failure(&"commerce.service_unavailable", "commerce service is unavailable")
	var mapped: DomainResult = _mapper.to_domain(state)
	if not mapped.is_ok:
		return mapped
	var player: Player = mapped.value
	var command_type := String(command.get("type", ""))
	var changed := command_type != "query_weapon_merchant"
	var operation := _execute_command(player, command_type, command)
	if not operation.is_ok:
		return operation
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
		"panel_bundle": _build_bundle(player, operation.value),
	})


## 从已提交存档重建玩家面板和商店/任务快照。
## [param state] 仓储返回的最新 revision 状态。
func build_bundle(state: PlayerStateRecord, operation: Dictionary = {}) -> Dictionary:
	var mapped: DomainResult = _mapper.to_domain(state) if state != null else DomainResult.failure(
		&"commerce.state_missing", "player state is missing"
	)
	return _build_bundle(mapped.value, operation) if mapped.is_ok else {}


func _execute_command(player: Player, command_type: String, command: Dictionary) -> DomainResult:
	match command_type:
		"query_weapon_merchant":
			return DomainResult.ok({"action": "query"})
		"buy_from_weapon_merchant":
			return _buy(player, command)
		"sell_to_weapon_merchant":
			return _sell(player, command)
		"accept_weapon_merchant_task":
			return _accept_task(player)
		"turn_in_weapon_merchant_task":
			return _turn_in_task(player, command)
	return DomainResult.failure(&"commerce.unknown_command", "unknown commerce command")


func _buy(player: Player, command: Dictionary) -> DomainResult:
	var revision_result := player.inventory.require_revision(int(command.get("inventory_revision", -1)))
	if not revision_result.is_ok:
		return revision_result
	var definition_id := String(command.get("definition_id", ""))
	var offer: Dictionary = _merchant.offer(definition_id)
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


func _sell(player: Player, command: Dictionary) -> DomainResult:
	var revision_result := player.inventory.require_revision(int(command.get("inventory_revision", -1)))
	if not revision_result.is_ok:
		return revision_result
	var instance_id := String(command.get("instance_id", ""))
	var quantity := int(command.get("quantity", 1))
	var item := player.inventory.find(instance_id)
	if item == null:
		return DomainResult.failure(&"inventory.item_not_found", "inventory item does not exist")
	var unit_price: int = _merchant.purchase_price(item.definition_id)
	var removed := player.inventory.remove_quantity(instance_id, quantity)
	if not removed.is_ok:
		return removed
	player.inventory.currency += unit_price * quantity
	return DomainResult.ok({
		"action": "sell", "definition_id": item.definition_id,
		"quantity": quantity, "price": unit_price * quantity,
	})


func _accept_task(player: Player) -> DomainResult:
	var current: Dictionary = player.quest_states.get(_task_id, {})
	var accepted: DomainResult = _task.accept(current)
	if not accepted.is_ok:
		return accepted
	player.quest_states[_task_id] = accepted.value
	return DomainResult.ok({"action": "accept_task"})


func _turn_in_task(player: Player, command: Dictionary) -> DomainResult:
	var revision_result := player.inventory.require_revision(int(command.get("inventory_revision", -1)))
	if not revision_result.is_ok:
		return revision_result
	var current: Dictionary = player.quest_states.get(_task_id, {})
	var completed: DomainResult = _task.turn_in(player.inventory, current)
	if not completed.is_ok:
		return completed
	var result: Dictionary = completed.value
	var milestone: Dictionary = result.get("milestone_reward", {})
	if not milestone.is_empty():
		var created := _catalog.create(String(milestone["definition_id"]), {
			"instance_id": _new_instance_id(String(milestone["definition_id"])),
			"quantity": int(milestone.get("quantity", 1)),
		})
		if not created.is_ok:
			return created
		var added := player.inventory.add_reward(created.value)
		if not added.is_ok:
			return added
	player.inventory.currency += int(result["currency_reward"])
	player.quest_states[_task_id] = result["state"]
	return DomainResult.ok({
		"action": "turn_in_task",
		"currency_reward": int(result["currency_reward"]),
		"milestone_reward": milestone.duplicate(true),
	})


func _build_bundle(player: Player, operation: Dictionary = {}) -> Dictionary:
	var bundle := _projector.build_bundle(player)
	var sell_items: Array[Dictionary] = []
	for item: GameItem in player.inventory.items():
		var view := item.to_view_dictionary()
		view["quantity"] = item.quantity
		view["unit_price"] = _merchant.purchase_price(item.definition_id)
		view["presentation"] = item.presentation.duplicate(true)
		sell_items.append(view)
	bundle["commerce"] = {
		"merchant": (_merchant.config().get("merchant", {}) as Dictionary).duplicate(true),
		"offers": _merchant.offers(),
		"sell_items": sell_items,
		"task": _task.snapshot(player.inventory, player.quest_states.get(_task_id, {})),
		"operation": operation.duplicate(true),
	}
	return bundle


func _new_instance_id(definition_id: String) -> String:
	var value := "shop.%d.%s" % [_next_instance_serial, definition_id]
	_next_instance_serial += 1
	return value
