class_name AuthoritativePlayerPanelService
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const PlayerStateMapperScript := preload("res://scripts/server/persistence/player_state_mapper.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/server/player_panels/player_panel_projector.gd"
)

var _catalog: ItemCatalog
var _mapper: PlayerStateMapper
var _projector: PlayerPanelProjector


## 初始化物品目录、持久化映射器和网络 DTO 投影器。
## 返回加载成功的服务实例或配置错误。
## 设计：应用服务只编排用例，不再持有物品类型、换装和属性计算规则。
func initialize() -> DomainResult:
	_catalog = ItemCatalogScript.new()
	var catalog_result := _catalog.initialize()
	if not catalog_result.is_ok:
		return catalog_result
	_mapper = PlayerStateMapperScript.new(_catalog)
	_projector = PlayerPanelProjectorScript.new(_catalog)
	return DomainResult.ok(self)


## 根据已登记角色状态执行查询或领域命令。
## [param state] 权威持久化聚合副本。
## [param command] 仅含操作意图、实例标识、目标与 revision 的命令。
## 返回 candidate 与完整 panel_bundle；查询命令的 candidate 与输入等价。
## 设计：服务不接触 peer 身份或仓储，调用方负责会话绑定与原子提交。
func execute(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	if state == null or _mapper == null or _projector == null:
		return DomainResult.failure(&"panels.service_unavailable", "player panel service is unavailable")
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok:
		return mapped
	var player: Player = mapped.value
	var command_type := StringName(command.get("type", ""))
	var changed := command_type != &"query"
	var operation := _execute_domain_command(player, command_type, command)
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
		"panel_bundle": _projector.build_bundle(player),
	})


## 从同一持久化记录构建人物、背包和战车一致快照。
## [param state] 已通过校验的权威玩家记录。
## 返回包含 transaction_revision 的三面板快照；映射失败时返回空字典。
func build_bundle(state: PlayerStateRecord) -> Dictionary:
	if state == null or _mapper == null or _projector == null:
		return {}
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok:
		push_error("Player panel projection failed: %s" % mapped.error_message)
		return {}
	return _projector.build_bundle(mapped.value)


## 将战斗模块预检通过的地面掉落加入权威玩家聚合。
## [param state] 自动存档服务持有的当前玩家记录副本。
## [param loot] 包含 loot_id、item_definition_id 与 quantity 的可信掉落 DTO。
## 返回待原子提交的 candidate 以及更新后的三面板快照。
## 设计：目录组装和背包规则在共享领域层完成，本服务不信任客户端提供的物品内容。
func grant_loot(state: PlayerStateRecord, loot: Dictionary) -> DomainResult:
	if state == null or _mapper == null or _catalog == null or _projector == null:
		return DomainResult.failure(&"loot.service_unavailable", "loot service is unavailable")
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok:
		return mapped
	var loot_id := String(loot.get("loot_id", ""))
	var definition_id := String(loot.get("item_definition_id", ""))
	var quantity := int(loot.get("quantity", 0))
	if loot_id.is_empty() or definition_id.is_empty() or quantity <= 0:
		return DomainResult.failure(&"loot.invalid_payload", "authoritative loot payload is invalid")
	var created := _catalog.create(definition_id, {
		"instance_id": loot_id,
		"quantity": quantity,
		"container_id": "main",
		"position_px": [0, 0],
		"footprint_px": [30, 30],
	})
	if not created.is_ok:
		return created
	var player: Player = mapped.value
	var received := player.receive_loot(created.value)
	if not received.is_ok:
		return received
	var persisted := _mapper.to_record(player)
	if not persisted.is_ok:
		return persisted
	return DomainResult.ok({
		"candidate": persisted.value,
		"panel_bundle": _projector.build_bundle(player),
	})


## 将应用层命令路由到 Player 聚合的公开行为。
## [param player] 本次事务内的玩家聚合。
## [param command_type] 命令类型。
## [param command] 命令参数。
## 返回领域操作结果或未知命令错误。
func _execute_domain_command(
	player: Player,
	command_type: StringName,
	command: Dictionary,
) -> DomainResult:
	match command_type:
		&"query":
			return DomainResult.ok()
		&"move_inventory_item":
			var position_result := _position_from_command(command)
			if not position_result.is_ok:
				return position_result
			return player.move_inventory_item(
				String(command.get("instance_id", "")),
				position_result.value,
				int(command.get("inventory_revision", -1)),
			)
		&"arrange_inventory":
			return player.arrange_inventory(int(command.get("inventory_revision", -1)))
		&"equip_vehicle_item":
			return player.equip_vehicle_item(
				String(command.get("instance_id", "")),
				int(command.get("location", -1)),
				int(command.get("inventory_revision", -1)),
				int(command.get("loadout_revision", -1)),
			)
		&"unequip_vehicle_item":
			return player.unequip_vehicle_item(
				int(command.get("location", -1)),
				int(command.get("inventory_revision", -1)),
				int(command.get("loadout_revision", -1)),
			)
		&"equip_character_item":
			return player.equip_character_item(
				String(command.get("instance_id", "")),
				String(command.get("character_slot", "")),
				int(command.get("inventory_revision", -1)),
				int(command.get("state_revision", -1)),
			)
		&"unequip_character_item":
			return player.unequip_character_item(
				String(command.get("character_slot", "")),
				int(command.get("inventory_revision", -1)),
				int(command.get("state_revision", -1)),
			)
		_:
			return DomainResult.failure(&"panels.unknown_command", "unknown player panel command")


## 解析背包移动命令中的二元素坐标。
## [param command] 客户端命令字典。
## 返回 Vector2i 或坐标格式错误。
func _position_from_command(command: Dictionary) -> DomainResult:
	var value: Variant = command.get("position_px")
	if not value is Array or value.size() != 2:
		return DomainResult.failure(&"inventory.invalid_position", "inventory position must contain two coordinates")
	return DomainResult.ok(Vector2i(int(value[0]), int(value[1])))
