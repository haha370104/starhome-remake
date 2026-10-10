class_name PlayerPanelProjector
extends RefCounted

const InventoryLayoutScript := preload("res://scripts/domain/inventory/inventory_layout.gd")

var _catalog: ItemCatalog
var _skill_progression_config: Dictionary
var _quest_catalog := RepeatableQuestCatalog.new()


## 初始化领域玩家到网络面板 DTO 的投影器。
## [param catalog] 用于显示战车定义名称的物品目录。
## [param skill_progression_config] 用于计算技能升级门槛的公开成长配置。
func _init(catalog: ItemCatalog, skill_progression_config: Dictionary = {}) -> void:
	_catalog = catalog
	_skill_progression_config = skill_progression_config.duplicate(true)
	_quest_catalog.initialize(catalog)


## 从同一 Player 聚合构建人物、背包和战车三份一致快照。
## [param player] 当前权威玩家聚合。
## 返回包含 transaction_revision 的完整面板 DTO。
## 设计：投影器只做格式转换，属性计算仍调用 Player 子对象的方法。
func build_bundle(player: Player) -> Dictionary:
	return {
		"transaction_revision": player.revision,
		"wallet": {"amethyst": player.amethyst.balance()},
		"character": _character_snapshot(player),
		"inventory": _inventory_snapshot(player.inventory),
		"vehicle": _vehicle_snapshot(player),
		"mission_journal": _journal_snapshot(player),
		"achievements": player.achievements.network_snapshot(),
		"food_status": player.food_status.to_dictionary(),
		"central": player.central.to_dictionary(),
		"vehicle_presets": player.vehicle_presets.to_dictionary(),
		"preset_server_time": int(Time.get_unix_time_from_system()),
	}


func build_llm_panels(player: Player) -> Dictionary:
	var items: Array[Dictionary] = []
	for item: GameItem in player.inventory.items():
		items.append({
			"instance_id": item.instance_id,
			"display_name": item.display_name,
			"type": _catalog.definition(item.definition_id).get("kind", "item"),
			"quantity": item.quantity,
		})
	return {
		"character": _character_snapshot(player),
		"inventory": {"items": items},
		"vehicle": _vehicle_snapshot(player),
	}


## 只投影对方可见的人物或战车资料，不附带背包及可用于操作的实例标识。
func build_public_view(player: Player, view: String) -> Dictionary:
	var snapshot := _character_snapshot(player) if view == "character" else _vehicle_snapshot(player)
	snapshot.erase("revision")
	snapshot.erase("character_id")
	snapshot.erase("vehicle_id")
	snapshot.erase("vehicle_definition_id")
	snapshot.erase("skills")
	var equipment_key := "worn_items" if view == "character" else "equipped"
	for item: Dictionary in snapshot[equipment_key]:
		item.erase("instance_id")
	return snapshot


## 只比较事务隔离过的组件，投影其最终变化；不读取仓库或历史收据。
## [param before] 提交前在线玩家。[param after] 已完成规则校验的候选。
## 返回提交后可发布的组件变化，事务版本由提交者填写。
func changes(before: Player, after: Player, include_quests := true) -> PlayerChange:
	var change := PlayerChange.new()
	if before.inventory != after.inventory:
		var previous := {}
		var definitions := {}
		for item: GameItem in before.inventory.items(): previous[item.instance_id] = item.to_view_dictionary()
		for item: GameItem in after.inventory.items():
			var row := item.to_view_dictionary()
			if previous.get(item.instance_id, {}) != row:
				change.items.append(row)
				definitions[item.definition_id] = true
			previous.erase(item.instance_id)
		for identity: String in previous:
			change.removed_items.append(identity)
			definitions[previous[identity].definition_id] = true
		change.inventory_revision = after.inventory.revision
		if before.inventory.currency != after.inventory.currency:
			change.inventory_currency = after.inventory.currency
		if include_quests:
			for definition_id: String in definitions:
				PlayerChange._merge_rows(change.quests, collection_changes(after, definition_id), "task_id")
	if before.character_equipment != after.character_equipment \
		and _equipment_rows(before.character_equipment.items()) != _equipment_rows(after.character_equipment.items()):
		change.character = _character_snapshot(after)
		change.skills.assign(change.character.skills)
		change.attributes_changed = true
	if before.vehicle.loadout.revision != after.vehicle.loadout.revision:
		change.vehicle = _vehicle_snapshot(after)
		change.attributes_changed = true
	if before.skills != after.skills:
		var modifiers := after.character_equipment.skill_modifiers()
		for id: String in SkillBook.ORDERED_SKILLS:
			var row := after.skills.to_view_row(id, modifiers, _skill_progression_config)
			if row != before.skills.to_view_row(id, modifiers, _skill_progression_config):
				PlayerChange._merge_rows(change.skills, [row], "id")
	if before.level != after.level:
		change.level = after.level
		change.attributes_changed = true
	if before.health != after.health: change.character_health = after.health
	if before.food_status != after.food_status and before.food_status.to_dictionary() != after.food_status.to_dictionary():
		change.food = after.food_status.to_dictionary()
		for kind in range(13, 18):
			if before.food_status.bonus(kind) != after.food_status.bonus(kind): change.attributes_changed = true
	if change.attributes_changed or before.vehicle.health != after.vehicle.health \
		or before.vehicle.reserve_energy != after.vehicle.reserve_energy or before.vehicle.working_energy != after.vehicle.working_energy:
		change.vehicle_stats = change.vehicle.stats if not change.vehicle.is_empty() else after.calculate_vehicle_stats()
	if before.vehicle_presets != after.vehicle_presets:
		change.presets = after.vehicle_presets.to_dictionary()
		change.preset_server_time = int(Time.get_unix_time_from_system())
	return change
## 投影只发生装备耐久变化的战车组件，避免为一次采矿重建人物和背包。
## [param player] 已更新实时耐久的权威玩家。
## 返回可合并到同一事务增量的战车变化。
func vehicle_durability_change(player: Player) -> PlayerChange:
	var change := PlayerChange.new()
	change.vehicle = _vehicle_snapshot(player)
	return change


## 提取少量已装配物品用于判断穿着是否变化，不投影其他面板。
## [param equipment] 人物穿着列表。
## 返回按固定槽位顺序排列的物品事实。
func _equipment_rows(equipment: Array) -> Array:
	return equipment.map(func(item: GameItem) -> Dictionary: return item.to_view_dictionary())


## 从持久化任务状态生成日志，材料进度复用收集任务领域规则。
## [param player] 权威玩家聚合；只查询，不接取或交付任务。
## 返回已接取或曾完成的任务列表，未登记分类保持空白。
func _journal_snapshot(player: Player) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for task_id: String in _quest_catalog.definitions:
		var state: Dictionary = player.quest_states.get(task_id, {})
		if not state.get("accepted", false) and int(state.get("completions", 0)) == 0:
			continue
		var entry := _quest_catalog.snapshot(player, _quest_catalog.definitions[task_id],
			_quest_catalog.day_key(int(Time.get_unix_time_from_system())))
		entry["category"] = 0
		entries.append(entry)
	return entries


## 构建人物面板 DTO。
## [param player] 当前玩家聚合。
## 返回身份、成长、技能和穿着视图。
func _character_snapshot(player: Player) -> Dictionary:
	var worn_items: Array[Dictionary] = []
	for clothing: Clothing in player.character_equipment.items():
		worn_items.append(_equipment_view(clothing, "character"))
	return {
		"revision": player.revision,
		"character_id": player.entity_id,
		"display_name": player.display_name,
		"sex": player.sex,
		"level": player.level,
		"profession": player.profession,
		"faction": player.faction,
		"residence": player.residence,
		"experience": player.experience,
		"health": player.health,
		"max_health": player.max_health,
		"description": player.description,
		"achievement_title": player.achievements.network_snapshot()["title_name"],
		"skills": player.skills.to_view_array(
			player.character_equipment, _skill_progression_config
		),
		"worn_items": worn_items,
		"buffs": [],
	}


## 构建像素背包 DTO。
## [param inventory] 玩家背包领域对象。
## 返回布局、数量、货币和物品视图。
func _inventory_snapshot(inventory: Inventory) -> Dictionary:
	var items: Array[Dictionary] = []
	for item: GameItem in inventory.items():
		items.append(item.to_view_dictionary())
	return {
		"revision": inventory.revision,
		"capacity": inventory.capacity,
		"container_id": InventoryLayoutScript.MAIN_CONTAINER_ID,
		"container_size": [InventoryLayoutScript.MAIN_SIZE.x, InventoryLayoutScript.MAIN_SIZE.y],
		"snap_size": InventoryLayoutScript.SNAP_SIZE,
		"item_count": items.size(),
		"currency": inventory.currency,
		"items": items,
	}


## 构建战车装配及汇总属性 DTO。
## [param player] 持有战车及人物穿着的玩家聚合根。
## 返回 Location 装备、表现层和战车自身计算的属性。
func _vehicle_snapshot(player: Player) -> Dictionary:
	var vehicle := player.vehicle
	var equipped: Array[Dictionary] = []
	for equipment: VehicleEquipment in vehicle.loadout.items():
		equipped.append(_equipment_view(equipment, "vehicle"))
	return {
		"revision": vehicle.loadout.revision,
		"vehicle_id": vehicle.vehicle_id,
		"vehicle_definition_id": vehicle.definition_id,
		"display_name": _catalog.display_name(vehicle.definition_id),
		"equipped": equipped,
		"stats": player.calculate_vehicle_stats(),
	}


## 构建带槽位和表现元数据的装备 DTO。
## [param equipment] 人物或战车装备实例。
## [param owner_kind] character 或 vehicle。
## 返回面板渲染所需的安全装备视图。
func _equipment_view(equipment: Equipment, owner_kind: String) -> Dictionary:
	var view := equipment.to_view_dictionary()
	var location: int = equipment.equipment_location if equipment is VehicleEquipment else 0
	view["owner_kind"] = owner_kind
	view["slot_id"] = (equipment as Clothing).character_slot \
		if equipment is Clothing else EquipmentSlotRegistry.slot_id(location)
	view["location"] = location
	view["location_name"] = "上衣" if equipment is Clothing \
		else EquipmentSlotRegistry.display_name(location)
	view["display_slot_id"] = -1 if equipment is Clothing \
		else EquipmentSlotRegistry.display_slot_id(location)
	view["special_series"] = "" if equipment is Clothing \
		else EquipmentSlotRegistry.special_series(location)
	view["special_row"] = -1 if equipment is Clothing \
		else EquipmentSlotRegistry.special_row(location)
	var dialog_presentation := equipment.presentation_for("dialog")
	var default_anchor := EquipmentSlotRegistry.dialog_anchor(location)
	view["dialog_presentation"] = dialog_presentation
	view["dialog_texture"] = String(dialog_presentation.get("dialog_texture", ""))
	view["dialog_anchor"] = _int_pair(
		dialog_presentation.get("dialog_anchor", [default_anchor.x, default_anchor.y]),
		[default_anchor.x, default_anchor.y],
	)
	view["dialog_origin"] = _int_pair(dialog_presentation.get("dialog_origin", [0, 0]), [0, 0])
	view["z_layer"] = int(dialog_presentation.get("z_layer", location))
	if equipment is VehicleEquipment and location in [0, 1]:
		# 中央组合预览的层次按槽位统一，不能混用旧 PNG 的 10/20 与 ALE 的 0/1。
		view["z_layer"] = {0: 10, 1: 20}[location]
	return view

## 将 JSON 数值对规范化为旧 UI 契约使用的整数数组。
## [param value] 待解析的外部值。
## [param fallback] 无效值时采用的默认数组。
## 返回含两个整数的数组。
func _int_pair(value: Variant, fallback: Array) -> Array:
	if value is Array and value.size() == 2:
		return [int(value[0]), int(value[1])]
	return fallback.duplicate()


## 只重新计算依赖指定材料的已登记任务，避免拾取刷新全部任务和面板。
## [param player] 已提交的玩家。[param definition_id] 数量变化的规范物品定义。
## 返回需要替换的任务条目。
func collection_changes(player: Player, definition_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for task_id: String in player.quest_states:
		var definition: Dictionary = _quest_catalog.definitions.get(task_id, {})
		for requirement: Dictionary in definition.get("requirements", []):
			if String(requirement.definition_id) != definition_id: continue
			var entry := _quest_catalog.snapshot(player, definition, _quest_catalog.day_key(int(Time.get_unix_time_from_system())))
			entry["category"] = 0
			entries.append(entry)
			break
	return entries
