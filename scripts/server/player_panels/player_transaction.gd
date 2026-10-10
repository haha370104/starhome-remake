class_name PlayerTransaction
extends RefCounted

# 候选只隔离本次用例会写的组件；其余组件共享只读引用。
const EQUIPMENT := ["inventory", "equipment"]
const COMMERCE := ["inventory", "equipment", "quests", "achievements", "daily", "wallet", "skills", "central"]


## 为用例建立只隔离写集的候选；失败时丢弃，不修改在线对象。
## [param source] 在线玩家。[param parts] 此用例允许写入的组件。[param catalog] 共享物品目录。
## [param inventory_definitions] 指定会被按定义修改的堆叠。
## [param inventory_instances] 指定会被按实例修改的物品。
## 返回候选玩家或物品恢复错误。
static func prepare(
	source: Player,
	parts: Array,
	catalog: ItemCatalog,
	inventory_definitions: Array[String] = [],
	inventory_instances: Array[String] = [],
	warehouse_cabinet: int = 0,
) -> DomainResult:
	var candidate := Player.new({})
	apply(candidate, source)
	if "inventory" in parts:
		var copied := _inventory(source.inventory, catalog, inventory_definitions, inventory_instances)
		if not copied.is_ok: return copied
		candidate.inventory = copied.value
	if "equipment" in parts or "food" in parts or "central" in parts or "achievements" in parts:
		candidate.vehicle = PlayerVehicle.new()
		for property: Dictionary in source.vehicle.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				candidate.vehicle.set(property.name, source.vehicle.get(property.name))
	if "equipment" in parts:
		candidate.character_equipment = CharacterEquipment.new()
		candidate.vehicle.loadout = VehicleLoadout.new(source.vehicle.loadout.revision)
		for item: GameItem in source.character_equipment.items() + source.vehicle.loadout.items():
			var copied := _item(item, catalog)
			if not copied.is_ok: return copied
			var restored: DomainResult = candidate.character_equipment.restore(copied.value) if item is Clothing \
				else candidate.vehicle.loadout.restore(copied.value)
			if not restored.is_ok: return restored
	if "warehouse" in parts:
		var loaded := source.warehouse.materialize()
		if not loaded.is_ok: return loaded
		candidate.warehouse = PersonalWarehouse.new()
		candidate.warehouse.revision = source.warehouse.revision
		candidate.warehouse._cabinets = source.warehouse._cabinets.duplicate()
		if warehouse_cabinet > 0:
			if warehouse_cabinet > source.warehouse.cabinet_count():
				return DomainResult.failure(&"warehouse.cabinet", "请先开通该储物柜")
			var copied := _inventory(source.warehouse._cabinets[warehouse_cabinet - 1], catalog, inventory_definitions, inventory_instances)
			if not copied.is_ok: return copied
			candidate.warehouse._cabinets[warehouse_cabinet - 1] = copied.value
	if "production" in parts: candidate.production = source.production.duplicate_queue()
	if "central" in parts: candidate.central = PlayerCentralController.restore(source.central.to_dictionary()).value
	if "presets" in parts: candidate.vehicle_presets = VehicleLoadoutPresets.restore(source.vehicle_presets.to_dictionary()).value
	if "skills" in parts: candidate.skills = SkillBook.new(source.skills.to_dictionary())
	if "quests" in parts: candidate.quest_states = source.quest_states.duplicate(true)
	if "achievements" in parts: candidate.achievements = PlayerAchievements.new(source.achievements.to_dictionary())
	if "daily" in parts: candidate.daily_activities = DailyActivityJournal.new(source.daily_activities.to_dictionary())
	if "wallet" in parts: candidate.amethyst = AmethystWallet.new(source.amethyst.balance())
	if "food" in parts: candidate.food_status = FoodStatus.new(source.food_status.to_dictionary())
	if candidate.vehicle != source.vehicle:
		candidate.vehicle.central = candidate.central
		candidate.vehicle.food_status = candidate.food_status
		candidate.vehicle.achievement_bonuses = candidate.achievements.bonuses()
	return DomainResult.ok(candidate)


## 在版本校验完成后提交候选字段，保留长期玩家对象身份。
## [param target] 唯一在线对象。[param candidate] 同步事务内已完整校验的候选。
static func apply(target: Player, candidate: Player) -> void:
	target.apply_state(candidate)


## 隔离背包及物品，复用物品事实映射，不复制人物或仓库。
## [param source] 原背包。[param catalog] 物品工厂。
## 返回可变候选或恢复错误。
static func _inventory(
	source: Inventory,
	catalog: ItemCatalog,
	definitions: Array[String] = [],
	instances: Array[String] = [],
) -> DomainResult:
	var inventory := Inventory.new(source.capacity, source.revision, source.currency)
	var items: Array[GameItem] = []
	var isolate_write_set := not definitions.is_empty() or not instances.is_empty()
	for item: GameItem in source.items():
		if isolate_write_set and item.definition_id not in definitions \
				and item.instance_id not in instances:
			items.append(item)
			continue
		var copied := _item(item, catalog)
		if not copied.is_ok: return copied
		items.append(copied.value)
	var restored := inventory.restore_items(items)
	return DomainResult.ok(inventory) if restored.is_ok else restored


## 复用完整物品状态映射，保留成长、绑定、位置及具体类型。
## [param source] 要隔离的物品。[param catalog] 物品工厂。
## 返回具体类型副本或错误。
static func _item(source: GameItem, catalog: ItemCatalog) -> DomainResult:
	var recorded := InventoryStackRecord.from_item(source, 0)
	if not recorded.is_ok: return recorded
	var state: Dictionary = recorded.value.item_state()
	if source is VehicleEquipment: state["equipment_location"] = source.equipment_location
	if source is Clothing: state["equipped_character_slot"] = source.character_slot
	return catalog.create(source.definition_id, state)
