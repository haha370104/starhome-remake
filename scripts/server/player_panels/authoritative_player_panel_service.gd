class_name AuthoritativePlayerPanelService
extends RefCounted

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/shared/player_panel_projector.gd"
)

var catalog: ItemCatalog
var _projector: PlayerPanelProjector
var _skill_progression_config: Dictionary = {}
var _rewards: RewardPipeline


## 初始化物品目录、持久化映射器和网络 DTO 投影器。
## 返回加载成功的服务实例或配置错误。
## 设计：应用服务只编排用例，不再持有物品类型、换装和属性计算规则。
## [param rewards] 同一服务器共享的奖励切面，省略时使用独立默认策略。
func initialize(rewards: RewardPipeline = null) -> DomainResult:
	catalog = ItemCatalogScript.new()
	var catalog_result := catalog.initialize()
	if not catalog_result.is_ok:
		return catalog_result
	var skill_config_result := JsonConfigLoader.load_dictionary(
		"res://data/gameplay/skill_progression.json"
	)
	if not skill_config_result.is_ok:
		return skill_config_result
	_skill_progression_config = skill_config_result.value
	var policy: DomainResult = DomainResult.ok(rewards) if rewards != null else RewardPolicyLoader.load_default()
	if not policy.is_ok: return policy
	_rewards = policy.value
	_projector = PlayerPanelProjectorScript.new(catalog, _skill_progression_config)
	return DomainResult.ok(self)


func build_public_view(player: Player, view: String) -> Dictionary:
	return _projector.build_public_view(player, view)


## 根据已登记角色状态执行查询或领域命令。
## [param state] 权威持久化聚合副本。
## [param command] 仅含操作意图、实例标识、目标与 revision 的命令。
## 返回候选及组件变化；完整面板仅用于显式查询。
## 设计：服务不接触 peer 身份或仓储，调用方负责会话绑定与原子提交。
func execute(state: Player, command: Dictionary) -> DomainResult:
	if state == null or _projector == null:
		return DomainResult.failure(&"panels.service_unavailable", "player panel service is unavailable")
	var kind := String(command.get("type", ""))
	var parts: Array = ["inventory"] if kind in ["move_inventory_item", "arrange_inventory", "split_inventory_item", "merge_inventory_item"] else PlayerTransaction.EQUIPMENT
	if kind == "capture_vehicle_preset": parts = ["presets"]
	elif kind == "apply_vehicle_preset": parts = ["inventory", "equipment", "presets"]
	elif kind == "use_inventory_item": parts = ["inventory", "food"]
	var mapped: DomainResult = DomainResult.ok(state) if kind == "query" else PlayerTransaction.prepare(state, parts, catalog)
	if not mapped.is_ok:
		return mapped
	var player: Player = mapped.value
	var command_type := StringName(command.get("type", ""))
	var changed := command_type != &"query"
	var operation := _execute_domain_command(player, command_type, command)
	if not operation.is_ok:
		return operation
	var candidate := player if changed else state
	return DomainResult.ok({
		"candidate": candidate,
		"changed": changed,
		"operation": operation.value,
		"panel_bundle": _projector.build_bundle(player) if not changed else {},
		"change": changes(state, player) if changed else null,
	})


## 比较隔离候选与在线对象，供面板和生产事务共用提交后的增量协议。
## [param before] 在线对象。[param after] 校验成功的候选。
## 返回受影响组件的最终值。
func changes(before: Player, after: Player) -> PlayerChange:
	return _projector.changes(before, after)


## 从同一持久化记录构建人物、背包和战车一致快照。
## [param state] 已通过校验的权威玩家记录。
## 返回包含 transaction_revision 的三面板快照；映射失败时返回空字典。
func build_bundle(state: Player) -> Dictionary:
	if state == null or _projector == null:
		return {}
	return _projector.build_bundle(state)


func build_llm_panels(state: Player) -> Dictionary:
	if state == null or _projector == null:
		return {}
	return _projector.build_llm_panels(state)


## 消费一个服务器内部玩法事件并向对应技能发放经验。
## [param state] 在线状态所有者持有的当前玩家。
## [param progression_event] 由权威移动或战斗模块生成的可信事件。
## 返回候选聚合、成长结果及最新面板快照；无效来源或零收益返回领域错误。
## 设计：客户端不能提交此事件；经验换算、升级与综合等级重算全部留在服务端应用边界。
func grant_skill_progression(
	state: Player,
	progression_event: Dictionary,
) -> DomainResult:
	if state == null or _projector == null \
			or _skill_progression_config.is_empty():
		return DomainResult.failure(&"progression.service_unavailable", "skill progression service is unavailable")
	var mapped := PlayerTransaction.prepare(state, ["skills"], catalog)
	if not mapped.is_ok:
		return mapped
	var player: Player = mapped.value
	var candidate := PlayerSkillProgression.new(player.skills, player.level, player.account_id, player.food_status)
	var granted := grant_progression(candidate, progression_event)
	if not granted.is_ok: return granted
	player.level = candidate.level
	return DomainResult.ok({
		"candidate": player,
		"progression": granted.value,
		"panel_bundle": _projector.build_bundle(player),
	})


## 在隔离的技能成长边界结算高频事件，按可见百分比决定是否需要完整面板。
## [param candidate] 由权威所有者提供的技能、综合等级、账号及食品候选。
## [param progression_event] 实际位移/伤害等内部事实，不接受客户端倍率。
## 返回成长与可见性变化；不读取装备目录、不创建面板、不持久化其他玩家字段。
func grant_progression(candidate: PlayerSkillProgression, progression_event: Dictionary) -> DomainResult:
	if candidate == null or _rewards == null or _skill_progression_config.is_empty():
		return DomainResult.failure(&"progression.service_unavailable", "skill progression service is unavailable")
	var converted := _experience_from_event(progression_event)
	if not converted.is_ok:
		return converted
	var value: Dictionary = converted.value
	var skill_id := String(value["skill_id"])
	var before_percent := candidate.skills.displayed_progress_percent(
		skill_id, _skill_progression_config
	)
	var granted := candidate.grant_experience(
		skill_id, float(value["amount"]), _skill_progression_config, _rewards, String(progression_event.get("source", ""))
	)
	if not granted.is_ok:
		return granted
	var progression: Dictionary = granted.value
	progression["source"] = String(progression_event.get("source", ""))
	var after_percent := candidate.skills.displayed_progress_percent(skill_id, _skill_progression_config)
	progression["visible_progress_changed"] = before_percent != after_percent \
		or bool(progression.get("upgraded", false))
	progression["progress_percent"] = after_percent
	return DomainResult.ok(progression)


## 把权威玩法事件换算为单次技能经验发放量。
## [param progression_event] 移动、有效伤害或未来系统显式发放事件。
## 返回 skill_id 与非负经验量；格式非法或不产生经验时返回错误。
## 设计：所有倍率和驾驶计重参数均来自服务端配置，事件只携带已确认的客观结果。
func _experience_from_event(progression_event: Dictionary) -> DomainResult:
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
			if skill_id != "mining":
				return DomainResult.failure(&"progression.invalid_event", "mining event targets another skill")
			var quantity := int(progression_event.get("quantity", 0))
			var mineral_coefficient := float(progression_event.get("experience_coefficient", 0.0))
			if quantity <= 0 or mineral_coefficient <= 0.0:
				return DomainResult.failure(&"progression.invalid_event", "mining event or configuration is invalid")
			amount = float(quantity) * mineral_coefficient * 1.5
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
	if String(command_type) in VehiclePresetCommands.COMMANDS:
		return VehiclePresetCommands.execute(player, command, int(Time.get_unix_time_from_system()))
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
		&"split_inventory_item", &"merge_inventory_item":
			return player.change_stack(String(command_type), String(command.get("instance_id", "")),
				int(command.get("quantity", 0)), int(command.get("inventory_revision", -1)),
				String(command.get("target_instance_id", "")))
		&"use_inventory_item":
			return player.use_inventory_item(String(command.get("instance_id", "")),
				int(command.get("inventory_revision", -1)), int(Time.get_unix_time_from_system()))
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


## 直接执行已经预检的拾取；背包领域规则保证失败没有部分合并。
## [param player] 唯一在线聚合。[param loot] 地面模块确认的掉落事实。
## 返回受影响的物品实例，成功后调用方必须同步完成地面提交。
func receive_loot(player: Player, loot: Dictionary) -> DomainResult:
	if loot.get("item") is GameItem:
		if player.inventory.find(loot.item.instance_id) != null:
			return DomainResult.failure(&"inventory.duplicate_item", "物品身份重复")
		var added := player.inventory.add_from_transfer(loot.item)
		if added.is_ok: player.inventory.commit_transfer()
		return DomainResult.ok(loot.item) if added.is_ok else added
	if String(loot.get("loot_id", "")).is_empty() or String(loot.get("item_definition_id", "")).is_empty() or int(loot.get("quantity", 0)) <= 0:
		return DomainResult.failure(&"loot.invalid_payload", "authoritative loot payload is invalid")
	var created := catalog.create(String(loot.item_definition_id), {
		"instance_id": String(loot.loot_id), "quantity": int(loot.quantity),
		"container_id": "main", "position_px": [0, 0], "footprint_px": [30, 30]})
	if not created.is_ok: return created
	return player.receive_loot(created.value)


## 只投影此次拾取涉及的物品与收集任务。
## [param player] 已完成提交的玩家。[param item] 合堆或新增的最终实例。
## 返回类型化变更；同步身份及基准版本由发布端补齐。
func pickup_change(player: Player, item: GameItem) -> PlayerChange:
	var change := PlayerChange.new()
	change.revision = player.revision
	change.inventory_revision = player.inventory.revision
	change.items.append(item.to_view_dictionary())
	change.quests = _projector.collection_changes(player, item.definition_id)
	return change


## 仅投影发生可见变化的技能，保留完整精度但不复制装备和背包。
## [param player] 已提交的玩家。[param skill_id] 发生变化的技能。[param upgraded] 是否刚升级。
## 返回可与同刻击杀合并的增量。
func progression_change(player: Player, skill_id: String, upgraded: bool) -> PlayerChange:
	var change := PlayerChange.new()
	change.revision = player.revision
	change.skills.append(player.skills.to_view_row(skill_id, player.character_equipment.skill_modifiers(), _skill_progression_config))
	if upgraded:
		change.level = player.level
		change.attributes_changed = true
	return change


## 为实时装备耐久变化生成最小战车增量，不复制人物和背包。
## [param player] 已应用模拟耐久的权威玩家。
## 返回可与采矿或战斗变化合并的增量。
func vehicle_durability_change(player: Player) -> PlayerChange:
	var change := _projector.vehicle_durability_change(player)
	change.revision = player.revision
	return change
