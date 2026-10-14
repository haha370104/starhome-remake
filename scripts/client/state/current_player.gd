class_name CurrentPlayer
extends Player

signal changed(player: Player)

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/shared/player_panel_projector.gd"
)

var last_change := PlayerPanelChange.new()
var _accepted_bundle: Dictionary = {}
var _previous: CurrentPlayer
var _catalog: ItemCatalog
var _projector: PlayerPanelProjector
var _skill_progression_config: Dictionary = {}


## 初始化客户端唯一的“自己”玩家聚合和本地配置目录。
## [param shared_catalog] 可由场景注入、供地面和背包共同组装物品的已初始化目录。
## 设计：网络 DTO 只在 apply_bundle 边界出现；面板与场景随后共享这个 Player 实例。
## [param shared_projector] 候选投影复用的无状态投影器，常规调用无需传入。
func _init(shared_catalog: ItemCatalog = null, shared_projector: PlayerPanelProjector = null) -> void:
	super({})
	_catalog = shared_catalog
	if shared_projector != null:
		_projector = shared_projector
		return
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
func apply_bundle(bundle: Dictionary) -> bool:
	if not bundle.get("character") is Dictionary or not bundle.get("inventory") is Dictionary or not bundle.get("vehicle") is Dictionary:
		return false
	var candidate := CurrentPlayer.new(_catalog, _projector)
	candidate._previous = self
	if not candidate._decode_bundle(bundle):
		candidate._previous = null
		return false
	candidate._previous = null
	last_change = PlayerPanelChange.between(_accepted_bundle, bundle)
	for field: String in ["entity_id", "display_name", "sex", "level", "profession", "faction", "residence", "description",
		"max_health", "health", "experience", "revision", "skills", "achievements", "character_equipment", "inventory",
		"vehicle", "central", "vehicle_presets", "food_status", "amethyst"]:
		set(field, candidate.get(field))
	_accepted_bundle = bundle.duplicate(true)
	changed.emit(self)
	return true


## 在隔离候选中恢复变化部分，复用上一投影中未改变的物品和聚合。
## [param bundle] 完整权威快照。
## 返回所有领域组件是否恢复成功；调用者成功后一次替换公开状态。
func _decode_bundle(bundle: Dictionary) -> bool:
	if _catalog == null or _projector == null \
		or not bundle.get("character") is Dictionary \
		or not bundle.get("inventory") is Dictionary \
		or not bundle.get("vehicle") is Dictionary:
		return false
	if not FoodStatus.valid_state(bundle.get("food_status", {})):
		return false
	var central_result := PlayerCentralController.restore(bundle.get("central", {}))
	if not central_result.is_ok: return false
	central = central_result.value
	var preset_result := VehicleLoadoutPresets.restore(bundle.get("vehicle_presets", {}))
	if not preset_result.is_ok: return false
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
	skills = _previous.skills if _previous != null and _previous._accepted_bundle.get("character", {}).get("skills") == character.get("skills") else SkillBook.new(skill_states)
	var achievement_snapshot: Dictionary = bundle.get("achievements", {})
	if not PlayerAchievements.valid_state({"counters": achievement_snapshot.get("counters", {})}):
		return false
	achievements = PlayerAchievements.new({"counters": achievement_snapshot.get("counters", {})})
	if _previous != null and _previous._accepted_bundle.get("inventory") == inventory_snapshot:
		inventory = _previous.inventory
	else:
		inventory = Inventory.new(
			int(inventory_snapshot.get("capacity", 40)),
			int(inventory_snapshot.get("revision", 0)),
			int(inventory_snapshot.get("currency", 0)),
		)
		var inventory_result := _restore_inventory(inventory_snapshot.get("items", []))
		if not inventory_result:
			return false
	var same_loadout := _previous != null and _previous.is_ready()
	for key: String in ["vehicle", "food_status", "achievements", "central"]:
		same_loadout = same_loadout and _previous._accepted_bundle.get(key) == bundle.get(key)
	same_loadout = same_loadout and _previous._accepted_bundle.get("character", {}).get("worn_items") == character.get("worn_items")
	for skill_id: String in SkillBook.ORDERED_SKILLS:
		same_loadout = same_loadout and skills.base_level(skill_id) == _previous.skills.base_level(skill_id)
	if same_loadout:
		vehicle = _previous.vehicle
		character_equipment = _previous.character_equipment
	else:
		character_equipment = CharacterEquipment.new()
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
	changed.emit(self)
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
		if _previous != null:
			var existing := _previous.inventory.find(String(raw_item.get("instance_id", "")))
			if existing != null:
				for old: Dictionary in _previous._accepted_bundle.get("inventory", {}).get("items", []):
					if old.get("instance_id") == existing.instance_id and old == raw_item:
						restored.append(existing)
						break
				if not restored.is_empty() and restored.back() == existing: continue
		var created := _catalog.create(String(raw_item.get("definition_id", "")), {
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
			"enhancement": raw_item.get("enhancement", {}),
			"clothing_improvement": raw_item.get("clothing_improvement", {}),
			"equipment_memory": raw_item.get("equipment_memory", {}),
			"vehicle_sockets": raw_item.get("vehicle_sockets", {}),
			"crystal_source": raw_item.get("crystal_source", {}),
			"austin_glens": raw_item.get("austin_glens", {}),
			"central_growth": raw_item.get("central_growth", {}),
			"sama": raw_item.get("sama", {}),
			"processing": raw_item.get("processing", {}),
			"extra_attributes": raw_item.get("extra_attributes", {}),
			"strengthening": raw_item.get("strengthening", {}),
			"equipment_quality": raw_item.get("equipment_quality", {}),
			"forging": raw_item.get("forging", {}),
			"usage": raw_item.get("usage", {}),
			"magazine": raw_item.get("magazine", {}),
			"crystal_cracks": raw_item.get("crystal_cracks", 0),
			"crystal_source_cracks": raw_item.get("crystal_source_cracks", 0),
		})
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
	var created := _catalog.create(String(raw_equipment.get("definition_id", "")), {
		"instance_id": raw_equipment.get("instance_id", ""),
		"equipped_character_slot": raw_equipment.get("slot_id", ""),
		"quantity": 1,
		"max_durability": raw_equipment.get("max_durability", 1),
		"durability": raw_equipment.get("durability", 1),
		"upgrade_level": raw_equipment.get("upgrade_level", 0),
		"enhancement": raw_equipment.get("enhancement", {}),
		"clothing_improvement": raw_equipment.get("clothing_improvement", {}),
		"vehicle_sockets": raw_equipment.get("vehicle_sockets", {}),
		"crystal_source": raw_equipment.get("crystal_source", {}),
		"austin_glens": raw_equipment.get("austin_glens", {}),
		"central_growth": raw_equipment.get("central_growth", {}),
		"sama": raw_equipment.get("sama", {}),
		"processing": raw_equipment.get("processing", {}),
		"extra_attributes": raw_equipment.get("extra_attributes", {}),
		"strengthening": raw_equipment.get("strengthening", {}),
		"equipment_quality": raw_equipment.get("equipment_quality", {}),
		"forging": raw_equipment.get("forging", {}),
		"usage": raw_equipment.get("usage", {}),
		"magazine": raw_equipment.get("magazine", {}),
		"locked": raw_equipment.get("locked", false),
		"bound": raw_equipment.get("bound", false),
		"equipment_location": raw_equipment.get("location", -1),
		"footprint_px": [45, 45],
	})
	return created.value if created.is_ok and created.value is Equipment else null


## 原位更新现有装备的耐久和使用余量，不重建背包与战车属性。
## [param owner_id] 权威消息对应的角色身份。
## [param conditions] 当前装配按实例编号导出的耐久状态。
## 返回消息是否完整合法并已原子应用；错误消息不改写现有物品。
func apply_equipment_conditions(owner_id: String, conditions: Dictionary) -> bool:
	if owner_id != entity_id or not is_ready(): return false
	var equipment: Array[Equipment] = []
	equipment.append_array(vehicle.loadout.items())
	equipment.append_array(character_equipment.items())
	var updates: Array[Dictionary] = []
	for item: Equipment in equipment:
		var raw: Variant = conditions.get(item.instance_id)
		if not raw is Dictionary or raw.get("definition_id") != item.definition_id: return false
		var durability_value := int(raw.get("durability", -1))
		if durability_value < 0 or durability_value > item.max_durability or int(raw.get("max_durability", -1)) != item.max_durability: return false
		var usage_result := EquipmentUsage.restore(raw.get("usage", {}))
		var magazine_result := WeaponMagazine.restore(raw.get("magazine", {}))
		if not usage_result.is_ok or not magazine_result.is_ok: return false
		updates.append({"item": item, "durability": durability_value, "usage": usage_result.value, "magazine": magazine_result.value})
	if updates.size() != conditions.size(): return false
	for update: Dictionary in updates:
		var item: Equipment = update.item
		item.durability = update.durability
		item.usage = update.usage
		item.magazine = update.magazine
	last_change = PlayerPanelChange.new()
	last_change.character_changed = true
	last_change.vehicle_changed = true
	_accepted_bundle = snapshot_bundle()
	changed.emit(self)
	return true
