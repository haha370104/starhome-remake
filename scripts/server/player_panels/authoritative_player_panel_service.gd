class_name AuthoritativePlayerPanelService
extends RefCounted

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const SkillProgressionScript := preload("res://scripts/domain/skills/skill_progression.gd")
const PlayerStateMapperScript := preload("res://scripts/server/persistence/player_state_mapper.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/shared/player_panel_projector.gd"
)

var _catalog: ItemCatalog
var _mapper: PlayerStateMapper
var _projector: PlayerPanelProjector
var _skill_progression_config: Dictionary = {}


## 初始化物品目录、持久化映射器和网络 DTO 投影器。
## 返回加载成功的服务实例或配置错误。
## 设计：应用服务只编排用例，不再持有物品类型、换装和属性计算规则。
func initialize() -> DomainResult:
	_catalog = ItemCatalogScript.new()
	var catalog_result := _catalog.initialize()
	if not catalog_result.is_ok:
		return catalog_result
	var skill_config_result := JsonConfigLoader.load_dictionary(
		"res://data/gameplay/skill_progression.json"
	)
	if not skill_config_result.is_ok:
		return skill_config_result
	_skill_progression_config = skill_config_result.value
	_mapper = PlayerStateMapperScript.new(_catalog)
	_projector = PlayerPanelProjectorScript.new(_catalog, _skill_progression_config)
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


## 将权威持久化记录还原为共享充血 Player 聚合，供同进程其他权威模块复用。
## [param state] 已通过仓储校验的玩家记录。
## 返回含完整固定装配对象的 Player，或映射失败原因。
## 设计：战斗、面板和存档必须共用同一映射边界，禁止再从 DTO 手工拼第二套战车状态。
func restore_player(state: PlayerStateRecord) -> DomainResult:
	if state == null or _mapper == null:
		return DomainResult.failure(&"panels.service_unavailable", "player mapper is unavailable")
	return _mapper.to_domain(state)


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


## 消费一个服务器内部玩法事件并向对应技能发放经验。
## [param state] 自动存档服务持有的当前玩家记录副本。
## [param progression_event] 由权威移动或战斗模块生成的可信事件。
## 返回候选聚合、成长结果及最新面板快照；无效来源或零收益返回领域错误。
## 设计：客户端不能提交此事件；经验换算、升级与综合等级重算全部留在服务端应用边界。
func grant_skill_progression(
	state: PlayerStateRecord,
	progression_event: Dictionary,
) -> DomainResult:
	if state == null or _mapper == null or _projector == null \
			or _skill_progression_config.is_empty():
		return DomainResult.failure(&"progression.service_unavailable", "skill progression service is unavailable")
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok:
		return mapped
	var player: Player = mapped.value
	var converted := _experience_from_event(progression_event, player)
	if not converted.is_ok:
		return converted
	var value: Dictionary = converted.value
	var skill_id := String(value["skill_id"])
	var before_percent := player.skills.displayed_progress_percent(
		skill_id, _skill_progression_config
	)
	var granted := player.grant_skill_experience(
		skill_id, float(value["amount"]), _skill_progression_config
	)
	if not granted.is_ok:
		return granted
	var persisted := _mapper.to_record(player)
	if not persisted.is_ok:
		return persisted
	var progression: Dictionary = granted.value
	progression["source"] = String(progression_event.get("source", ""))
	progression["granted_experience"] = float(value["amount"])
	var after_percent := player.skills.displayed_progress_percent(skill_id, _skill_progression_config)
	progression["visible_progress_changed"] = before_percent != after_percent \
		or bool(progression.get("upgraded", false))
	progression["progress_percent"] = after_percent
	return DomainResult.ok({
		"candidate": persisted.value,
		"progression": progression,
		"panel_bundle": _projector.build_bundle(player),
	})


## 把权威玩法事件换算为单次技能经验发放量。
## [param progression_event] 移动、有效伤害或未来系统显式发放事件。
## 返回 skill_id 与非负经验量；格式非法或不产生经验时返回错误。
## 设计：所有倍率和驾驶计重参数均来自服务端配置，事件只携带已确认的客观结果。
## [param player] 调用方传入的 `player` 参数。
func _experience_from_event(progression_event: Dictionary, player: Player = null) -> DomainResult:
	var source := String(progression_event.get("source", ""))
	var skill_id := String(progression_event.get("skill_id", ""))
	var sources: Dictionary = _skill_progression_config.get("experience_sources", {})
	var amount := 0.0
	match source:
		"effective_damage":
			var multipliers: Dictionary = sources.get("weapon_damage_multiplier", {})
			amount = float(progression_event.get("damage", 0)) \
				* float(multipliers.get(skill_id, 0.0))
		"accepted_driving_movement":
			if skill_id != "driving":
				return DomainResult.failure(&"progression.invalid_event", "driving event targets another skill")
			var distance := float(progression_event.get("distance", 0.0))
			var weight := float(progression_event.get("vehicle_weight", 0.0))
			var weight_cap := float(sources.get("driving_weight_cap", 0.0))
			var experience_unit := float(sources.get("driving_experience_unit", 0.0))
			if distance < 0.0 or weight < 0.0 or weight_cap <= 0.0 or experience_unit <= 0.0:
				return DomainResult.failure(&"progression.invalid_event", "driving event or configuration is invalid")
			amount = distance * minf(weight, weight_cap) / experience_unit
		"mined_material":
			if skill_id != "mining" or player == null:
				return DomainResult.failure(&"progression.invalid_event", "mining event targets another skill")
			var quantity := int(progression_event.get("quantity", 0))
			var mineral_coefficient := float(progression_event.get("experience_coefficient", 0.0))
			var equivalents_per_level := float(sources.get("mining_iron_equivalent_per_level", 0.0))
			var threshold := SkillProgressionScript.get_need_points(
				&"mining", player.skills.base_level("mining"), _skill_progression_config
			)
			if quantity <= 0 or mineral_coefficient <= 0.0 or equivalents_per_level <= 0.0 \
					or not threshold.is_ok:
				return DomainResult.failure(&"progression.invalid_event", "mining event or configuration is invalid")
			amount = float(quantity) * mineral_coefficient * float(threshold.value) \
				/ equivalents_per_level
		"authoritative_action":
			amount = float(progression_event.get("amount", 0.0))
		_:
			return DomainResult.failure(&"progression.invalid_event", "unknown progression event source")
	if skill_id.is_empty() or not is_finite(amount) or amount <= 0.0:
		return DomainResult.failure(&"progression.no_experience", "event produces no skill experience")
	return DomainResult.ok({"skill_id": skill_id, "amount": amount})


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
				bool(command.get("_authoritative_vehicle_combat_active", false)),
			)
		&"unequip_vehicle_item":
			return player.unequip_vehicle_item(
				int(command.get("location", -1)),
				int(command.get("inventory_revision", -1)),
				int(command.get("loadout_revision", -1)),
				bool(command.get("_authoritative_vehicle_combat_active", false)),
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
