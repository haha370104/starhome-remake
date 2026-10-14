class_name AuthoritativeGardenService
extends RefCounted

const COMMANDS := ["query_garden", "harvest_garden"]
var rules: BotanicalGardenCatalog
var _catalog: ItemCatalog
var _mapper: PlayerStateMapper
var _projector: PlayerPanelProjector


## 复用服务器物品目录；采摘服务没有独立玩家或冷却存储。
## [param catalog] 权威物品目录。[param rewards] 同一奖励策略。
## 返回规则与投影初始化结果。
func initialize(catalog: ItemCatalog, rewards: RewardPipeline = null) -> DomainResult:
	_catalog = catalog
	var loaded := BotanicalGardenCatalog.load_default()
	if not loaded.is_ok: return loaded
	rules = loaded.value
	for plant: BotanicalGardenCatalog.Plant in rules.plants:
		if _catalog.definition(plant.item_id).is_empty():
			return DomainResult.failure(&"garden.item", "采摘物品未注册")
	_mapper = PlayerStateMapper.new(catalog, rewards)
	loaded = JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json")
	if not loaded.is_ok: return loaded
	_projector = PlayerPanelProjector.new(catalog, loaded.value)
	return DomainResult.ok(self)


## 在隔离候选上执行采摘；调用方仅在完整提交成功后发布背包与冷却。
## [param state] 已捕获权威实时位置的存档。[param command] 不可信采摘意图。
## [param now] 服务端秒数；测试可注入时钟，生产使用系统时间。
## 返回候选记录和面板结果或拒绝原因。
func execute(state: PlayerStateRecord, command: Dictionary, now: int = -1) -> DomainResult:
	if state == null or command.get("type") not in COMMANDS:
		return DomainResult.failure(&"garden.command", "采摘命令无效")
	if now < 0: now = int(Time.get_unix_time_from_system())
	var changed: bool = command.type == "harvest_garden"
	if not changed:
		return DomainResult.ok({"changed": false, "panel_bundle": build_bundle(state, {}, now)})
	if state.character_health <= 0:
		return DomainResult.failure(&"garden.health", "当前无法采摘")
	var version: Variant = command.get("inventory_revision")
	if not (version is int or version is float) or not is_finite(float(version)) or float(version) != floorf(float(version)) or version < 0 or version > 9007199254740991 or not command.get("plant_id") is String:
		return DomainResult.failure(&"garden.command", "采摘命令缺少目标或背包版本")
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok: return mapped
	var player: Player = mapped.value
	var checked := player.inventory.require_revision(int(command.inventory_revision))
	if not checked.is_ok: return checked
	var plant := rules.find(command.plant_id)
	if plant == null: return DomainResult.failure(&"garden.plant", "采摘目标不存在")
	var fruit := _catalog.create(plant.item_id, {"instance_id": "garden." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": 1})
	if not fruit.is_ok: return fruit
	checked = player.garden.harvest(rules, plant, player.map_id, player.position, player.inventory, fruit.value, now)
	if not checked.is_ok: return checked
	var saved := _mapper.to_record(player)
	if not saved.is_ok: return saved
	return DomainResult.ok({"candidate": saved.value, "changed": true,
		"operation": {"message": "采摘获得：%s × 1" % fruit.value.display_name}, "panel_bundle": {}})


## 从已提交的玩家快照发布当前地图成熟状态，避免提前确认失败事务。
## [param state] 已提交人物。[param operation] 本次成功消息。[param now] 权威秒数。
## 返回背包和采摘展示投影。
func build_bundle(state: PlayerStateRecord, operation: Dictionary = {}, now: int = -1) -> Dictionary:
	if now < 0: now = int(Time.get_unix_time_from_system())
	var rows: Array[Dictionary] = []
	if state.map_id == rules.map_id:
		for plant: BotanicalGardenCatalog.Plant in rules.plants:
			rows.append({"plant_id": plant.id, "remaining_seconds": state.garden.remaining(plant.id, now)})
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok: return {}
	var bundle := _projector.build_bundle(mapped.value)
	bundle["garden"] = {"map_id": state.map_id, "plants": rows, "message": String(operation.get("message", ""))}
	return bundle
