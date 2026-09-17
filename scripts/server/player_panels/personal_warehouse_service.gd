class_name PersonalWarehouseService
extends RefCounted

const COMMANDS := ["query_personal_warehouse", "deposit_warehouse_item", "withdraw_warehouse_item", "expand_personal_warehouse"]

var _catalog: ItemCatalog
var _rules: WarehouseRules
var _mapper: PlayerStateMapper
var _projector: PlayerPanelProjector


## 组装仓库专用规则与现有玩家映射、投影，服务不拥有另一份玩家存档。
## [param rewards] 同一服务器的奖励切面，供人物状态映射保持一致。
## 返回初始化结果。
func initialize(rewards: RewardPipeline = null) -> DomainResult:
	_catalog = ItemCatalog.new()
	var loaded := _catalog.initialize()
	if not loaded.is_ok: return loaded
	loaded = WarehouseRules.load_default()
	if not loaded.is_ok: return loaded
	_rules = loaded.value
	_mapper = PlayerStateMapper.new(_catalog, rewards)
	loaded = JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json")
	if not loaded.is_ok: return loaded
	_projector = PlayerPanelProjector.new(_catalog, loaded.value)
	return DomainResult.ok(self)


## 在隔离玩家聚合上执行仓库命令，人物身份和地点只取权威存档。
## [param state] 当前已绑定会话的玩家记录。
## [param command] 不可信物品身份、数量、柜号和版本。
## 返回候选记录、操作结果与面板；调用方仍须完成一次原子仓储提交。
func execute(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	var kind: Variant = command.get("type")
	if kind not in COMMANDS or state == null or _mapper == null:
		return DomainResult.failure(&"warehouse.command", "仓库命令无效")
	var cabinet_value: Variant = command.get("cabinet", 1)
	if not _integer(cabinet_value, 1, PersonalWarehouse.MAX_CABINETS):
		return DomainResult.failure(&"warehouse.cabinet", "储物柜编号无效")
	var cabinet := int(cabinet_value)
	var changed: bool = kind != "query_personal_warehouse"
	if changed and not _rules.allows(state.map_id):
		return DomainResult.failure(&"warehouse.location", "请在龙之城或基地大厅使用个人仓库")
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok: return mapped
	var player: Player = mapped.value
	var operation := {"cabinet": cabinet, "message": ""}
	if changed:
		var checked := _change(player, command, kind, cabinet)
		if not checked.is_ok: return checked
		operation.merge(checked.value, true)
	cabinet = mini(int(operation.cabinet), player.warehouse.cabinet_count())
	operation.cabinet = cabinet
	var candidate := state.duplicate_record()
	if changed:
		var saved := _mapper.to_record(player)
		if not saved.is_ok: return saved
		candidate = saved.value
	var projected := _bundle(player, cabinet, String(operation.message))
	if not projected.is_ok: return projected
	return DomainResult.ok({"candidate": candidate, "changed": changed, "operation": operation, "panel_bundle": projected.value})


## 严格验证库存版本与数量，再委托仓库完成同一人物的存取或扩容。
## [param player] 当前隔离领域聚合。
## [param command] 原始网络意图。
## [param kind] 已验证的命令类型。
## [param cabinet] 已验证范围的柜号。
## 返回实际结算结果或拒绝原因。
func _change(player: Player, command: Dictionary, kind: String, cabinet: int) -> DomainResult:
	for key: String in ["inventory_revision", "warehouse_revision"]:
		if not _integer(command.get(key), 0, 9007199254740991):
			return DomainResult.failure(&"warehouse.command", "仓库操作缺少有效版本")
	var inventory_revision := int(command.inventory_revision)
	var warehouse_revision := int(command.warehouse_revision)
	var checked := player.inventory.require_revision(inventory_revision)
	if not checked.is_ok: return checked
	if kind == "expand_personal_warehouse":
		if not command.get("confirm_expansion") is bool or not command.confirm_expansion:
			return DomainResult.failure(&"warehouse.confirm", "请确认本次扩容的紫晶费用")
		checked = player.warehouse.expand(player.amethyst, _rules, warehouse_revision)
		if not checked.is_ok: return checked
		player.inventory.commit_transfer()
		return DomainResult.ok({"cabinet": checked.value.cabinet_count, "message": "已开通第%d个储物柜，消耗%d紫晶" % [checked.value.cabinet_count, checked.value.cost]})
	var id: Variant = command.get("instance_id")
	var quantity: Variant = command.get("quantity")
	if not id is String or id.is_empty() or not _integer(quantity, 1, 1000000):
		return DomainResult.failure(&"warehouse.quantity", "请选择物品并输入有效的存取数量")
	var identity := "warehouse." + Crypto.new().generate_random_bytes(16).hex_encode()
	var deposit := kind == "deposit_warehouse_item"
	checked = player.warehouse.transfer(player.inventory, cabinet, deposit, id, int(quantity), inventory_revision, warehouse_revision, identity)
	if not checked.is_ok: return checked
	return DomainResult.ok({"cabinet": cabinet, "message": "%s%d个物品" % ["已存入" if deposit else "已取出", int(quantity)]})


## 从最终已提交的状态重建当前柜，不能发布提交前的候选版本。
## [param state] 仓储已确认的玩家记录。
## [param operation] 本次结果中的柜号及消息。
## 返回统一玩家和仓库快照。
func build_bundle(state: PlayerStateRecord, operation: Dictionary = {}) -> Dictionary:
	var result := _mapper.to_domain(state)
	if not result.is_ok: return {}
	var bundle := _bundle(result.value, int(operation.get("cabinet", 1)), String(operation.get("message", "")))
	return bundle.value if bundle.is_ok else {}


## 为当前柜构造只读UI投影，离开基地后只显示使用限制而不加载仓库物品。
## [param player] 已映射的当前人物。
## [param cabinet] 请求查看的柜号。
## [param message] 服务端操作结果。
## 返回安全投影或仓库加载错误。
func _bundle(player: Player, cabinet: int, message: String) -> DomainResult:
	var available := _rules.allows(player.map_id)
	var rows: Array[Dictionary] = []
	if available:
		var loaded := player.warehouse.materialize()
		if not loaded.is_ok: return loaded
		for item: GameItem in player.warehouse.items(cabinet):
			var view := item.to_view_dictionary()
			view["presentation"] = item.presentation.duplicate(true)
			rows.append(view)
	var bundle := _projector.build_bundle(player)
	bundle["personal_warehouse"] = {"revision": player.warehouse.revision, "cabinet": cabinet,
		"cabinet_count": player.warehouse.cabinet_count(), "maximum_cabinets": PersonalWarehouse.MAX_CABINETS,
		"capacity": InventoryLayout.ITEM_LIMIT, "items": rows, "available": available,
		"expansion_cost": _rules.expansion_cost, "amethyst": player.amethyst.balance(),
		"message": message if available else "请返回龙之城或基地大厅存取物品", "inventory_revision": player.inventory.revision}
	return DomainResult.ok(bundle)


## 拒绝布尔值、分数、无穷和超界的网络数量，不能静默截断。
## [param value] 未可信的输入值。
## [param minimum] 包含的下限。
## [param maximum] 包含的上限。
## 返回是否为范围内的整数。
static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum
