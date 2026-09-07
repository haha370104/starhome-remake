class_name AuthoritativeManufacturingService
extends RefCounted

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const RecipeBookScript := preload(
	"res://scripts/domain/manufacturing/manufacturing_recipe_book.gd"
)
const PlayerStateMapperScript := preload("res://scripts/server/persistence/player_state_mapper.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/server/player_panels/player_panel_projector.gd"
)

const COMMAND_TYPES := ["query_manufacturing", "craft_recipe"]
const STATION_NAMES := {
	"tailoring": "裁缝机", "cooking": "烹饪台", "refining": "提炼机",
	"alloy": "合金制造机", "maintenance": "维护包制造机",
	"equipment_manufacturing": "主装备制造机", "auxiliary_manufacturing": "附属装备制造机",
}

var _item_catalog: ItemCatalog
var _recipe_book: RefCounted
var _mapper: PlayerStateMapper
var _projector: PlayerPanelProjector
var _progression_config: Dictionary = {}
var _random := RandomNumberGenerator.new()
var _next_instance_serial := 1
var _facility_maps: Dictionary = {}


## 初始化权威制造所需的物品、配方、技能和持久化映射边界。
## 返回加载成功的服务实例或具体配置错误。
func initialize() -> DomainResult:
	_item_catalog = ItemCatalogScript.new()
	var item_result := _item_catalog.initialize()
	if not item_result.is_ok:
		return item_result
	_recipe_book = RecipeBookScript.new()
	var recipe_result: DomainResult = _recipe_book.initialize(_item_catalog)
	if not recipe_result.is_ok:
		return recipe_result
	var skill_result := JsonConfigLoader.load_dictionary(
		"res://data/gameplay/skill_progression.json"
	)
	if not skill_result.is_ok:
		return skill_result
	_progression_config = skill_result.value
	_mapper = PlayerStateMapperScript.new(_item_catalog)
	_projector = PlayerPanelProjectorScript.new(_item_catalog, _progression_config)
	var facilities := JsonConfigLoader.load_dictionary("res://data/world/manufacturing_facilities_v1.json")
	if not facilities.is_ok:
		return facilities
	_facility_maps = facilities.value.get("maps", {})
	_random.randomize()
	return DomainResult.ok(self)


## 判断玩家面板命令是否属于制造服务。
## [param command_type] 网络命令中的稳定类型标识。
## 返回是否由本服务处理。
func handles(command_type: String) -> bool:
	return command_type in COMMAND_TYPES


## 查询配方或执行一次由服务器随机判定的生产事务。
## [param state] 当前权威玩家存档副本。
## [param command] 只含设施、配方与背包 revision 的客户端意图。
## 返回待提交存档、制造投影和统一玩家面板快照。
func execute(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	if state == null or _mapper == null or _recipe_book == null:
		return DomainResult.failure(&"manufacturing.service_unavailable", "manufacturing service is unavailable")
	var station_id := String(command.get("station_id", ""))
	if not STATION_NAMES.has(station_id):
		return DomainResult.failure(&"manufacturing.station_invalid", "manufacturing station is invalid")
	if not _map_has_station(state.map_id, station_id):
		return DomainResult.failure(&"manufacturing.station_unavailable", "当前地图没有该生产设施")
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok:
		return mapped
	var player: Player = mapped.value
	var command_type := String(command.get("type", ""))
	var operation := {"action": "query", "station_id": station_id}
	var changed := command_type == "craft_recipe"
	if changed:
		var revision_result := player.inventory.require_revision(
			int(command.get("inventory_revision", -1))
		)
		if not revision_result.is_ok:
			return revision_result
		var recipe: RefCounted = _recipe_book.recipe(String(command.get("recipe_id", "")))
		if recipe == null or not recipe.belongs_to_station(station_id):
			return DomainResult.failure(&"manufacturing.recipe_missing", "recipe is not available at this station")
		var executed: DomainResult = recipe.execute(
			player,
			_item_catalog,
			_new_instance_id(recipe.product_definition_id),
			_random.randf(),
			_progression_config,
		)
		if not executed.is_ok:
			return executed
		operation = (executed.value as Dictionary).duplicate(true)
		operation["action"] = "craft"
		operation["station_id"] = station_id
	var candidate := state.duplicate_record()
	if changed:
		var persisted := _mapper.to_record(player)
		if not persisted.is_ok:
			return persisted
		candidate = persisted.value
	return DomainResult.ok({
		"candidate": candidate,
		"changed": changed,
		"operation": operation,
		"panel_bundle": _build_bundle(player, station_id, operation),
	})


## 从已提交存档重建指定生产设施的最新面板快照。
## [param state] 仓储中的权威玩家记录。
## [param operation] 最近一次生产结果。
## 返回合并制造数据的玩家面板 bundle；映射失败返回空字典。
func build_bundle(state: PlayerStateRecord, operation: Dictionary = {}) -> Dictionary:
	var mapped: DomainResult = _mapper.to_domain(state) if state != null else DomainResult.failure(
		&"manufacturing.state_missing", "player state is missing"
	)
	var station_id := String(operation.get("station_id", "tailoring"))
	return _build_bundle(mapped.value, station_id, operation) if mapped.is_ok else {}


## 构造生产设施配方、玩家材料进度和三面板一致快照。
## [param player] 当前事务内玩家聚合。
## [param station_id] 已验证的生产设施类型。
## [param operation] 最近一次生产结果。
## 返回可经 JSON/RPC 传输的纯字典。
func _build_bundle(
	player: Player,
	station_id: String,
	operation: Dictionary = {},
) -> Dictionary:
	var bundle := _projector.build_bundle(player)
	var recipes: Array[Dictionary] = []
	for recipe: RefCounted in _recipe_book.recipes_for_station(station_id):
		recipes.append(recipe.to_view_dictionary(player, _item_catalog))
	bundle["manufacturing"] = {
		"station_id": station_id,
		"display_name": String(STATION_NAMES.get(station_id, "生产设施")),
		"recipes": recipes,
		"operation": operation.duplicate(true),
	}
	return bundle


## 生成当前服务进程内唯一的制造产物实例 ID。
## [param definition_id] 产物稳定定义标识。
## 返回不依赖客户端输入的实例标识。
func _new_instance_id(definition_id: String) -> String:
	var value := "crafted.%s.%d.%s" % [Crypto.new().generate_random_bytes(16).hex_encode(), _next_instance_serial, definition_id]
	_next_instance_serial += 1
	return value


## 核验权威存档所在地图是否登记了所请求的设施。
## [param map_id] 服务端持有的当前位置地图，不接受客户端覆盖。
## [param station_id] 请求的设施类型。
## 返回是否允许查询和生产；保留旧快照不能绕过换图限制。
func _map_has_station(map_id: String, station_id: String) -> bool:
	for facility: Dictionary in _facility_maps.get(map_id, []):
		if String(facility.get("station_id", "")) == station_id:
			return true
	return false
