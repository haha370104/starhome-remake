class_name CurrentPlayer
extends Player

signal changed(player: Player)

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/shared/player_panel_projector.gd"
)

var last_change := PlayerPanelChange.new()
var _accepted_bundle: Dictionary = {}
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
	var candidate := PlayerPanelDecoder.new(_catalog, _projector, self, _accepted_bundle, is_ready())
	if not candidate.decode(bundle): return false
	last_change = PlayerPanelChange.between(_accepted_bundle, bundle)
	for field: String in ["entity_id", "display_name", "sex", "level", "profession", "faction", "residence", "description",
		"max_health", "health", "experience", "revision", "skills", "achievements", "character_equipment", "inventory",
		"vehicle", "central", "vehicle_presets", "food_status", "amethyst"]:
		set(field, candidate.get(field))
	_accepted_bundle = bundle.duplicate(true)
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
