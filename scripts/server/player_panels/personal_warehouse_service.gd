class_name PersonalWarehouseService
extends RefCounted

const COMMANDS := ["query_personal_warehouse", "deposit_warehouse_item", "withdraw_warehouse_item", "expand_personal_warehouse", "move_warehouse_item", "arrange_warehouse", "split_warehouse_item"]

var _catalog: ItemCatalog
var _rules: WarehouseRules
var _projector: PlayerPanelProjector


## 组装仓库专用规则与现有玩家映射、投影，服务不拥有另一份玩家存档。
## [param _rewards] 同一服务器的奖励切面，供人物状态映射保持一致。
## 返回初始化结果。
func initialize(_rewards: RewardPipeline = null) -> DomainResult:
	_catalog = ItemCatalog.new()
	var loaded := _catalog.initialize()
	if not loaded.is_ok: return loaded
	loaded = WarehouseRules.load_default()
	if not loaded.is_ok: return loaded
	_rules = loaded.value
	loaded = JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json")
	if not loaded.is_ok: return loaded
	_projector = PlayerPanelProjector.new(_catalog, loaded.value)
	return DomainResult.ok(self)


## 在隔离玩家聚合上执行仓库命令，人物身份和地点只取权威存档。
## [param state] 当前已绑定会话的在线玩家。
## [param command] 不可信物品身份、数量、柜号和版本。
## 返回候选记录、操作结果与面板；调用方仍须完成一次原子仓储提交。
func execute(state: Player, command: Dictionary) -> DomainResult:
	var kind: Variant = command.get("type")
	if kind not in COMMANDS or state == null:
		return DomainResult.failure(&"warehouse.command", "仓库命令无效")
	var cabinet_value: Variant = command.get("cabinet", 1)
	if not _integer(cabinet_value, 1, PersonalWarehouse.MAX_CABINETS):
		return DomainResult.failure(&"warehouse.cabinet", "储物柜编号无效")
	var cabinet := int(cabinet_value)
	var changed: bool = kind != "query_personal_warehouse"
	if changed and not _rules.allows(state.map_id):
		return DomainResult.failure(&"warehouse.location", "请在龙之城或基地大厅使用个人仓库")
	if changed:
		for key: String in ["inventory_revision", "warehouse_revision"]:
			if not _integer(command.get(key), 0, 9007199254740991):
				return DomainResult.failure(&"warehouse.command", "仓库操作缺少有效版本")
		var checked := state.inventory.require_revision(int(command.inventory_revision))
		if not checked.is_ok: return checked
		if int(command.warehouse_revision) != state.warehouse.revision:
			return DomainResult.failure(&"warehouse.revision", "仓库状态已更新，请重试")
	if kind not in ["query_personal_warehouse", "expand_personal_warehouse", "arrange_warehouse"] \
		and (not command.get("instance_id") is String or command.instance_id.is_empty()):
		return DomainResult.failure(&"warehouse.item", "请选择物品")
	var parts := ["warehouse"]
	if kind in ["deposit_warehouse_item", "withdraw_warehouse_item"]: parts.append("inventory")
	if kind == "expand_personal_warehouse": parts.append("wallet")
	var instances: Array[String] = []
	if command.get("instance_id") is String and kind != "arrange_warehouse": instances.append(command.instance_id)
	var mapped: DomainResult = PlayerTransaction.prepare(state, parts, _catalog, [], instances,
		0 if kind == "expand_personal_warehouse" else cabinet) if changed else DomainResult.ok(state)
	if not mapped.is_ok: return mapped
	var player: Player = mapped.value
	var operation := {"cabinet": cabinet, "message": ""}
	if changed:
		var checked := _change(player, command, kind, cabinet)
		if not checked.is_ok: return checked
		operation.merge(checked.value, true)
	cabinet = mini(int(operation.cabinet), player.warehouse.cabinet_count())
	operation.cabinet = cabinet
	var candidate := player if changed else state
	var projected := _bundle(player, cabinet, String(operation.message))
	if not projected.is_ok: return projected
	if kind == "expand_personal_warehouse": projected.value.merge(_projector.build_bundle(player))
	return DomainResult.ok({"candidate": candidate, "changed": changed, "operation": operation, "change": _projector.changes(state, player, false) if changed else null, "panel_bundle": projected.value})


## 严格验证库存版本与数量，再委托仓库完成同一人物的存取或扩容。
## [param player] 当前隔离领域聚合。
## [param command] 原始网络意图。
## [param kind] 已验证的命令类型。
## [param cabinet] 已验证范围的柜号。
## 返回实际结算结果或拒绝原因。
func _change(player: Player, command: Dictionary, kind: String, cabinet: int) -> DomainResult:
	var inventory_revision := int(command.inventory_revision)
	var warehouse_revision := int(command.warehouse_revision)
	var checked: DomainResult
	if kind == "expand_personal_warehouse":
		if not command.get("confirm_expansion") is bool or not command.confirm_expansion:
			return DomainResult.failure(&"warehouse.confirm", "请确认本次扩容的紫晶费用")
		checked = player.warehouse.expand(player.amethyst, _rules, warehouse_revision)
		if not checked.is_ok: return checked
		return DomainResult.ok({"cabinet": checked.value.cabinet_count, "message": "已开通第%d个储物柜，消耗%d紫晶" % [checked.value.cabinet_count, checked.value.cost]})
	if kind == "arrange_warehouse":
		checked = player.warehouse.arrange(cabinet, warehouse_revision)
		return checked if not checked.is_ok else DomainResult.ok({"cabinet": cabinet, "message": ""})
	if kind == "split_warehouse_item":
		var split_amount: Variant = command.get("quantity")
		if not _integer(split_amount, 1, 1000000):
			return DomainResult.failure(&"warehouse.quantity", "拆分数量无效")
		checked = player.warehouse.split_item(cabinet, String(command.get("instance_id", "")),
			int(split_amount), warehouse_revision)
		return checked if not checked.is_ok else DomainResult.ok({"cabinet": cabinet, "message": ""})
	var position: Variant = command.get("position_px")
	if not position is Array or position.size() != 2 \
		or not _integer(position[0], 0, InventoryLayout.MAIN_SIZE.x - 1) \
		or not _integer(position[1], 0, InventoryLayout.MAIN_SIZE.y - 1):
		return DomainResult.failure(&"warehouse.position", "物品位置无效")
	var center := Vector2i(int(position[0]), int(position[1]))
	if kind == "move_warehouse_item":
		checked = player.warehouse.move_item(cabinet, command.instance_id, center, warehouse_revision)
	else:
		checked = player.warehouse.transfer(player.inventory, cabinet, kind == "deposit_warehouse_item",
			command.instance_id, center, inventory_revision, warehouse_revision)
	if not checked.is_ok: return checked
	return DomainResult.ok({"cabinet": cabinet, "message": ""})


## 从最终已提交状态重建仓库快照。
func build_bundle(state: Player, operation: Dictionary = {}) -> Dictionary:
	if state == null: return {}
	var bundle := _bundle(state, int(operation.get("cabinet", 1)), String(operation.get("message", "")))
	return bundle.value if bundle.is_ok else {}


func _bundle(player: Player, cabinet: int, message: String) -> DomainResult:
	var available := _rules.allows(player.map_id)
	var rows: Array[Dictionary] = []
	var loaded := player.warehouse.materialize()
	if not loaded.is_ok: return loaded
	for item: GameItem in player.warehouse.items(cabinet):
		rows.append(item.to_view_dictionary())
	var warehouse := {"revision": player.warehouse.revision, "cabinet": cabinet,
		"cabinet_count": player.warehouse.cabinet_count(), "maximum_cabinets": PersonalWarehouse.MAX_CABINETS,
		"capacity": InventoryLayout.ITEM_LIMIT, "items": rows, "available": available,
		"expansion_cost": _rules.expansion_cost, "amethyst": player.amethyst.balance(),
		"message": message if available else "请返回龙之城或基地大厅存取物品", "inventory_revision": player.inventory.revision}
	return DomainResult.ok({"transaction_revision": player.revision, "personal_warehouse": warehouse})


## 拒绝布尔值、分数、无穷和超界的网络数量，不能静默截断。
## [param value] 未可信的输入值。
## [param minimum] 包含的下限。
## [param maximum] 包含的上限。
## 返回是否为范围内的整数。
static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum
