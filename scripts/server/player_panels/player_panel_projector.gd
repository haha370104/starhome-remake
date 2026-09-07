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
		"character": _character_snapshot(player),
		"inventory": _inventory_snapshot(player.inventory),
		"vehicle": _vehicle_snapshot(player),
		"mission_journal": _journal_snapshot(player),
	}


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
	return view

## 将 JSON 数值对规范化为旧 UI 契约使用的整数数组。
## [param value] 待解析的外部值。
## [param fallback] 无效值时采用的默认数组。
## 返回含两个整数的数组。
func _int_pair(value: Variant, fallback: Array) -> Array:
	if value is Array and value.size() == 2:
		return [int(value[0]), int(value[1])]
	return fallback.duplicate()
