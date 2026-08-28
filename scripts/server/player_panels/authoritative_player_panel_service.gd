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
