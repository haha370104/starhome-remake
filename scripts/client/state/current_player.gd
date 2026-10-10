class_name CurrentPlayer
extends Player

signal changed(player: Player)

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/shared/player_panel_projector.gd"
)

var _catalog: ItemCatalog
var _projector: PlayerPanelProjector
var _skill_progression_config: Dictionary = {}


## 初始化客户端唯一的“自己”玩家聚合和本地配置目录。
## [param shared_catalog] 可由场景注入、供地面和背包共同组装物品的已初始化目录。
## 设计：网络 DTO 只在 apply_bundle 边界出现；面板与场景随后共享这个 Player 实例。
func _init(shared_catalog: ItemCatalog = null) -> void:
	super({})
	_catalog = shared_catalog
	if _catalog == null:
		_catalog = ItemCatalogScript.new()
		var initialized := _catalog.initialize()
		if not initialized.is_ok:
			push_error("Current player item catalog failed: %s" % initialized.error_message)
			return
	var skill_config_result := JsonConfigLoader.load_dictionary(
		"res://data/gameplay/skill_progression.json"
	)
	if not skill_config_result.is_ok:
		push_error("Current player skill config failed: %s" % skill_config_result.error_message)
		return
	_skill_progression_config = skill_config_result.value
	_projector = PlayerPanelProjectorScript.new(_catalog, _skill_progression_config)


## 用同事务版本的权威快照重建当前玩家聚合。
## [param bundle] 服务端下发的人物、背包和战车快照组。
## 返回快照是否完整、合法并已应用。
func _restore_bundle(bundle: Dictionary) -> bool:
	if _catalog == null or _projector == null \
		or not bundle.get("character") is Dictionary \
		or not bundle.get("inventory") is Dictionary \
		or not bundle.get("vehicle") is Dictionary:
		return false
	if not FoodStatus.valid_state(bundle.get("food_status", {})):
		return false
	var central_result := PlayerCentralController.restore(bundle.get("central", {}))
	if not central_result.is_ok:
		return false
	central = central_result.value
	var preset_result := VehicleLoadoutPresets.restore(bundle.get("vehicle_presets", {}))
	if not preset_result.is_ok:
		return false
	vehicle_presets = preset_result.value
	food_status = FoodStatus.new(bundle.get("food_status", {}))
	amethyst = AmethystWallet.new(int(bundle.get("wallet", {}).get("amethyst", 0)))
	var character: Dictionary = bundle["character"]
	var inventory_snapshot: Dictionary = bundle["inventory"]
	var vehicle_snapshot: Dictionary = bundle["vehicle"]
	var skill_states: Dictionary = {}
	for skill: Variant in character.get("skills", []):
		if skill is Dictionary:
			skill_states[String(skill.get("id", ""))] = {
				"level": int(skill.get("base_level", 0)),
				"current_exp": int(skill.get("experience", 0)),
				"fractional_exp": float(skill.get("fractional_experience", 0.0)),
			}
	entity_id = String(character.get("character_id", ""))
	display_name = String(character.get("display_name", ""))
	sex = String(character.get("sex", "male"))
	level = maxi(10, int(character.get("level", 10)))
	profession = String(character.get("profession", "新兵"))
	faction = String(character.get("faction", "龙之城"))
	residence = String(character.get("residence", "龙之城基地"))
	description = String(character.get("description", ""))
	max_health = maxi(1, int(character.get("max_health", 1)))
	health = clampi(int(character.get("health", max_health)), 0, max_health)
	experience = maxi(0, int(character.get("experience", 0)))
	revision = maxi(0, int(bundle.get("transaction_revision", 0)))
	skills = SkillBook.new(skill_states)
	var achievement_snapshot: Dictionary = bundle.get("achievements", {})
	if not PlayerAchievements.valid_state({"counters": achievement_snapshot.get("counters", {})}):
		return false
	achievements = PlayerAchievements.new({"counters": achievement_snapshot.get("counters", {})})
	character_equipment = CharacterEquipment.new()
	inventory = Inventory.new(
		int(inventory_snapshot.get("capacity", 40)),
		int(inventory_snapshot.get("revision", 0)),
		int(inventory_snapshot.get("currency", 0)),
	)
	var inventory_result := _restore_inventory(inventory_snapshot.get("items", []))
	if not inventory_result:
		return false
	vehicle = PlayerVehicle.new({
		"vehicle_id": vehicle_snapshot.get("vehicle_id", ""),
		"definition_id": vehicle_snapshot.get("vehicle_definition_id", ""),
		"loadout_revision": vehicle_snapshot.get("revision", 0),
		"max_health": vehicle_snapshot.get("stats", {}).get("max_health", 1),
		"health": vehicle_snapshot.get("stats", {}).get("health", 1),
		"reserve_energy_capacity": vehicle_snapshot.get("stats", {}).get("reserve_energy_capacity", 0.0),
		"reserve_energy": vehicle_snapshot.get("stats", {}).get("reserve_energy", 0.0),
		"working_energy_capacity": vehicle_snapshot.get("stats", {}).get("working_energy_capacity", 0.0),
		"working_energy": vehicle_snapshot.get("stats", {}).get("working_energy", 0.0),
		"output_power": vehicle_snapshot.get("stats", {}).get("output_power", 0.0),
	})
	if not _restore_equipment(character.get("worn_items", []), vehicle_snapshot.get("equipped", [])):
		return false
	vehicle.central = central
	vehicle.central_rules = _catalog.central_rules
	vehicle.achievement_bonuses = achievements.bonuses()
	vehicle.food_status = food_status
	refresh_clothing_bonuses()
	vehicle.reconcile_loadout_state(false)
	return true


## 从当前领域对象重新生成面板 DTO，避免保留第二份可变快照状态。
## 返回人物、背包、战车与事务 revision 的完整投影。
func snapshot_bundle() -> Dictionary:
	return _projector.build_bundle(self) if _projector != null else {}


## 查询当前玩家是否已经收到过权威快照。
## 返回身份、战车和投影器均可用时为 true。
func is_ready() -> bool:
	return revision >= 0 and not entity_id.is_empty() \
		and vehicle != null and not vehicle.vehicle_id.is_empty() and _projector != null


## 从背包 DTO 恢复具体类型物品。
## [param raw_items] 服务端安全物品视图数组。
## 返回所有物品创建和布局校验均成功时为 true。
func _restore_inventory(raw_items: Variant) -> bool:
	if not raw_items is Array:
		return false
	var restored: Array[GameItem] = []
	for raw_item: Variant in raw_items:
		if not raw_item is Dictionary:
			return false
		var created := create_inventory_item(raw_item)
		if not created.is_ok:
			return false
		restored.append(created.value)
	return inventory.restore_items(restored).is_ok


## 从人物和战车装备 DTO 恢复固定槽位对象。
## [param worn_items] 人物服装视图数组。
## [param vehicle_items] 战车装备视图数组。
## 返回所有装备类型和固定槽位均一致时为 true。
func _restore_equipment(worn_items: Variant, vehicle_items: Variant) -> bool:
	if not worn_items is Array or not vehicle_items is Array:
		return false
	for raw_clothing: Variant in worn_items:
		var created := _create_equipment(raw_clothing)
		if not created is Clothing or not character_equipment.restore(created).is_ok:
			return false
	for raw_vehicle: Variant in vehicle_items:
		var created := _create_equipment(raw_vehicle)
		if not created is VehicleEquipment or not vehicle.loadout.restore(created).is_ok:
			return false
	return true


## 将单个装备 DTO 还原为具体装备实例。
## [param raw_equipment] 服务端安全装备视图。
## 返回具体装备；格式或目录错误时返回 null。
func _create_equipment(raw_equipment: Variant) -> Equipment:
	if not raw_equipment is Dictionary:
		return null
	var item_state := {
		"instance_id": raw_equipment.get("instance_id", ""),
		"equipped_character_slot": raw_equipment.get("slot_id", ""),
		"quantity": 1,
		"max_durability": raw_equipment.get("max_durability", 1),
		"durability": raw_equipment.get("durability", 1),
		"upgrade_level": raw_equipment.get("upgrade_level", 0),
		"locked": raw_equipment.get("locked", false),
		"bound": raw_equipment.get("bound", false),
		"equipment_location": raw_equipment.get("location", -1),
		"footprint_px": [45, 45],
	}
	for field: String in [
		"enhancement", "clothing_improvement", "vehicle_sockets", "crystal_source",
		"austin_glens", "central_growth", "sama", "processing", "extra_attributes",
		"strengthening", "equipment_quality", "forging", "usage", "magazine",
	]:
		if raw_equipment.has(field):
			item_state[field] = raw_equipment[field]
	var created := _catalog.create(String(raw_equipment.get("definition_id", "")), item_state)
	return created.value if created.is_ok and created.value is Equipment else null


## 在完整快照全部通过校验后一次替换字段，失败不污染当前玩家。
## [param bundle] 已通过同步版本检查的完整快照。
## 返回是否成功应用。
func apply_bundle(bundle: Dictionary) -> bool:
	var candidate := CurrentPlayer.new(_catalog)
	if not candidate._restore_bundle(bundle): return false
	apply_state(candidate)
	changed.emit(self)
	return true


## 预检全部组件后原位提交；只在装配变化时替换对应装备对象。
## [param change] 已验证结构和版本的增量。
## 返回应用结果，拒绝时所有已有对象保持原值。
func apply_change(change: PlayerChange) -> bool:
	if change.inventory_revision >= 0 and change.inventory_revision <= inventory.revision: return false
	var next_clothing := character_equipment
	var next_vehicle := vehicle
	if not change.character.is_empty():
		if change.character.character_id != entity_id or int(change.character.max_health) != max_health: return false
		next_clothing = CharacterEquipment.new()
		for row: Variant in change.character.worn_items:
			var equipment := _create_equipment(row)
			if not equipment is Clothing or not next_clothing.restore(equipment).is_ok: return false
	if not change.vehicle.is_empty():
		if not change.vehicle.get("equipped") is Array or not PlayerChange._count(change.vehicle.get("revision")) \
			or not _valid_vehicle_stats(change.vehicle.get("stats")): return false
		next_vehicle = PlayerVehicle.new({"vehicle_id": change.vehicle.get("vehicle_id", ""),
			"definition_id": change.vehicle.get("vehicle_definition_id", ""), "loadout_revision": change.vehicle.revision})
		for row: Variant in change.vehicle.equipped:
			var equipment := _create_equipment(row)
			if not equipment is VehicleEquipment or not next_vehicle.loadout.restore(equipment).is_ok: return false
	if not change.vehicle_stats.is_empty() and not _valid_vehicle_stats(change.vehicle_stats): return false
	if change.character_health > max_health: return false
	var pending: Array[GameItem] = []
	var updates: Dictionary[String, Dictionary] = {}
	var structural := not change.removed_items.is_empty()
	if change.inventory_revision >= 0:
		for item: GameItem in inventory.items():
			if item.instance_id not in change.removed_items: pending.append(item)
	for row: Dictionary in change.items:
		var existing := inventory.find(String(row.instance_id))
		if existing != null:
			var expected := existing.to_view_dictionary()
			expected["amount"] = row.amount
			expected["position_px"] = row.get("position_px")
			if int(row.amount) > existing.max_stack or existing.definition_id != row.definition_id: return false
			if expected == row:
				updates[existing.instance_id] = row
				continue
		var created := create_inventory_item(row)
		if not created.is_ok or created.value.to_view_dictionary() != row: return false
		if existing != null: pending[pending.find(existing)] = created.value
		else: pending.append(created.value)
		structural = true
	if change.inventory_revision >= 0:
		if pending.size() > inventory.capacity: return false
		var layouts: Array = []
		for item: GameItem in pending: layouts.append(updates.get(item.instance_id, item.to_layout_dictionary()))
		if not InventoryLayout.validate(layouts).is_ok: return false
	# 所有组件预检结束后才写入现有对象；订阅者尚未收到任何通知。
	for identity: String in updates:
		var item := inventory.find(identity)
		item.quantity = int(updates[identity].amount)
		item.position_px = Vector2i(int(updates[identity].position_px[0]), int(updates[identity].position_px[1]))
	if structural: inventory.restore_items(pending)
	if change.inventory_revision >= 0: inventory.revision = change.inventory_revision
	if change.inventory_currency >= 0: inventory.currency = change.inventory_currency
	character_equipment = next_clothing
	vehicle = next_vehicle
	if not change.food.is_empty(): food_status = FoodStatus.new(change.food)
	vehicle.food_status = food_status
	vehicle.central = central
	vehicle.central_rules = _catalog.central_rules
	if not change.presets.is_empty(): vehicle_presets = VehicleLoadoutPresets.restore(change.presets).value
	if change.character_health >= 0: health = change.character_health
	if not change.skills.is_empty():
		var skill_states := skills.to_dictionary()
		for row: Dictionary in change.skills:
			skill_states[String(row.id)] = {"level": int(row.base_level), "current_exp": int(row.experience),
				"fractional_exp": float(row.fractional_experience)}
		skills = SkillBook.new(skill_states)
	if change.level >= 0: level = change.level
	if not change.achievements.is_empty():
		achievements.apply_counters(change.achievements)
	if not change.achievements.is_empty() or not change.vehicle.is_empty(): vehicle.achievement_bonuses = achievements.bonuses()
	if not change.character.is_empty() or not change.vehicle.is_empty(): refresh_clothing_bonuses()
	if change.attributes_changed: vehicle.reconcile_loadout_state(false)
	if not change.vehicle.is_empty(): _apply_vehicle_stats(change.vehicle.stats)
	if not change.vehicle_stats.is_empty(): _apply_vehicle_stats(change.vehicle_stats)
	revision = change.revision
	return true


## 校验增量携带的战车资源值，拒绝缺项、非数值或超界输入。
## [param stats] 服务端战车属性投影。
## 返回是否可在事务提交阶段直接应用。
func _valid_vehicle_stats(stats: Variant) -> bool:
	if not stats is Dictionary: return false
	for key: String in ["health", "max_health", "reserve_energy", "reserve_energy_capacity", "working_energy", "working_energy_capacity", "output_power"]:
		if not (stats.get(key) is int or stats.get(key) is float) or not is_finite(float(stats[key])) or stats[key] < 0: return false
	return stats.max_health > 0 and stats.health <= stats.max_health \
		and stats.reserve_energy <= stats.reserve_energy_capacity and stats.working_energy <= stats.working_energy_capacity


## 同步已经校验的资源数值，不重新建立装备或外观。
## [param stats] 已提交事务的最终属性。
func _apply_vehicle_stats(stats: Dictionary) -> void:
	vehicle.max_health = int(stats.max_health)
	vehicle.health = int(stats.health)
	vehicle.reserve_energy_capacity = float(stats.reserve_energy_capacity)
	vehicle.reserve_energy = float(stats.reserve_energy)
	vehicle.working_energy_capacity = float(stats.working_energy_capacity)
	vehicle.working_energy = float(stats.working_energy)
	vehicle.output_power = float(stats.output_power)


## 通过共享目录恢复背包物品，完整快照和增量使用同一字段映射。
## [param raw_item] 已确认是字典的物品视图。
## 返回具体领域物品或格式错误。
func create_inventory_item(raw_item: Dictionary) -> DomainResult:
	var item_state := {
		"instance_id": raw_item.get("instance_id", ""),
		"quantity": raw_item.get("amount", 1),
		"container_id": raw_item.get("container_id", "main"),
		"position_px": raw_item.get("position_px", [0, 0]),
		"footprint_px": raw_item.get("footprint_px", [30, 30]),
		"locked": raw_item.get("locked", false),
		"bound": raw_item.get("bound", false),
		"max_durability": raw_item.get("max_durability", 0),
		"durability": raw_item.get("durability", 0),
		"upgrade_level": raw_item.get("upgrade_level", 0),
	}
	for field: String in [
		"enhancement", "clothing_improvement", "equipment_memory", "vehicle_sockets",
		"crystal_source", "austin_glens", "central_growth", "sama", "processing",
		"extra_attributes", "strengthening", "equipment_quality", "forging", "usage",
		"magazine", "crystal_cracks", "crystal_source_cracks",
	]:
		if raw_item.has(field):
			item_state[field] = raw_item[field]
	return _catalog.create(String(raw_item.get("definition_id", "")), item_state)
