class_name PlayerPanelServiceFixture
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")
const InventoryStackRecordScript := preload("res://scripts/server/persistence/inventory_stack_record.gd")
const EquipmentSlotRecordScript := preload("res://scripts/server/persistence/equipment_slot_record.gd")
const PanelServiceScript := preload("res://scripts/server/player_panels/authoritative_player_panel_service.gd")

var _service: AuthoritativePlayerPanelService
var _state: PlayerStateRecord
var _mapper: PlayerStateMapper


## 创建仅用于服务端面板单元测试的内存状态夹具。
## 返回初始化成功的桥接器或目录/聚合错误。
## 设计：该类不属于运行时代码，只为服务端服务和 UI 投影测试构造稳定聚合。
func initialize() -> DomainResult:
	_service = PanelServiceScript.new()
	var service_result := _service.initialize()
	if not service_result.is_ok:
		return service_result
	var state_data: Dictionary = PlayerStateRecordScript.new().to_dictionary()
	state_data.merge({
		"schema_version": PlayerStateRecord.CURRENT_SCHEMA_VERSION,
		"account_id": "account.player.local",
		"account_name": "player.local",
		"account_status": "active",
		"character_id": "player.local",
		"display_name": "H番茄花园",
		"revision": 0,
		"inventory_revision": 0,
		"vehicle_loadout_revision": 0,
		"inventory_capacity": 40,
		"currency": 1000,
		"character_sex": "male",
		"character_level": 10,
		"character_profession": "殖民战士",
		"character_faction": "龙之城",
		"character_residence": "基地大厅一层",
		"character_description": "荣耀版复刻工程的面板测试角色。",
		"inventory_stacks": [
			_stack("inventory.spare_engine", "beginner_engine", 0, [0, 0], false, 900),
			_stack("inventory.training_shirt", "male_sleeveless_shirt", 1, [60, 0], true, 64),
		],
		"equipment_slots": [
			_equipment("equipment.chassis", "chassis", 0, 0, "recruit_tank", 1020),
			_equipment("equipment.weapon", "primary_weapon", 1, 1, "recruit_energy_cannon", 900),
			_equipment("equipment.engine", "propulsion", 3, 3, "beginner_engine", 900),
		],
		"character_max_health": 100,
		"character_health": 100,
		"character_experience": 0,
		"character_skills": _initial_skill_states(),
		"vehicle_id": "vehicle.player.local",
		"vehicle_definition_id": "recruit_tank",
		"vehicle_max_health": 70,
		"vehicle_health": 70,
		"reserve_energy_capacity": 10000.0,
		"reserve_energy": 10000.0,
		"working_energy_capacity": 100.0,
		"working_energy": 100.0,
		"output_power": 21.0,
		"map_id": "yian_harbor_hall_floor_1",
		"map_instance_id": "test.instance.1",
		"position": [720.0, 540.0],
		"facing_direction": 6,
		"checkpoint_id": "offline.debug",
	}, true)
	var state_result := PlayerStateRecordScript.from_dictionary(state_data)
	if not state_result.is_ok:
		return state_result
	_state = state_result.value
	_mapper = PlayerStateMapper.new(_service.catalog)
	return DomainResult.ok(self)


## 将当前测试记录还原为正式 Player 聚合。
## 夹具外部需要调用当前服务 API 时使用此方法，不直接把存档 DTO 当作领域对象。
func current_player() -> DomainResult:
	if _mapper == null or _state == null:
		return DomainResult.failure(&"panels.offline_unavailable", "offline player mapper is unavailable")
	return _mapper.to_domain(_state)


## 执行离线调试面板命令并返回与服务器相同的 panel_bundle。
## [param command] 面板查询或事务意图。
## 返回成功快照或领域拒绝。
func execute(command: Dictionary) -> DomainResult:
	if _service == null or _state == null:
		return DomainResult.failure(&"panels.offline_unavailable", "offline panel authority is unavailable")
	var player_result := current_player()
	if not player_result.is_ok:
		return player_result
	var result: DomainResult = _service.execute(player_result.value, command)
	if not result.is_ok:
		return result
	var value: Dictionary = result.value
	if bool(value.get("changed", false)):
		var recorded: DomainResult = _mapper.to_record(value["candidate"])
		if not recorded.is_ok:
			return recorded
		_state = recorded.value
		_state.revision += 1
	var current := current_player()
	if not current.is_ok:
		return current
	return DomainResult.ok(_service.build_bundle(current.value))


## 在显式离线调试中复用正式服务端的掉落入包事务。
## [param loot] 由离线战斗权威生成的掉落 DTO。
## 返回更新后的三面板快照或目录、容量、布局错误。
## 设计：本方法不自行构造物品，只桥接 AuthoritativePlayerPanelService 的正式规则。
func grant_loot(loot: Dictionary) -> DomainResult:
	if _service == null or _state == null:
		return DomainResult.failure(&"loot.offline_unavailable", "offline loot authority is unavailable")
	var player_result := current_player()
	if not player_result.is_ok:
		return player_result
	var result: DomainResult = _service.receive_loot(player_result.value, loot)
	if not result.is_ok:
		return result
	var recorded: DomainResult = _mapper.to_record(player_result.value)
	if not recorded.is_ok:
		return recorded
	_state = recorded.value
	_state.revision += 1
	var current := current_player()
	if not current.is_ok:
		return current
	return DomainResult.ok(_service.build_bundle(current.value))


## 在显式离线调试中消费与正式服务器相同的技能成长事件。
## [param progression_event] 离线战斗权威生成的移动或最终有效伤害事件。
## 返回更新后的三面板快照或成长规则拒绝。
## 设计：即使处于离线模式，经验换算和综合等级仍复用 AuthoritativePlayerPanelService。
func grant_skill_progression(progression_event: Dictionary) -> DomainResult:
	if _service == null or _state == null:
		return DomainResult.failure(&"progression.offline_unavailable", "offline progression authority is unavailable")
	var player_result := current_player()
	if not player_result.is_ok:
		return player_result
	var result: DomainResult = _service.grant_skill_progression(player_result.value, progression_event)
	if not result.is_ok:
		return result
	var value: Dictionary = result.value
	var recorded: DomainResult = _mapper.to_record(value["candidate"])
	if not recorded.is_ok:
		return recorded
	_state = recorded.value
	var current := current_player()
	if not current.is_ok:
		return current
	return DomainResult.ok({
		"panel_bundle": _service.build_bundle(current.value),
		"progression": value["progression"],
	})


## 创建离线初始装备记录字典。
## [param instance_id] 稳定装备实例标识。
## [param slot_id] 业务槽位名。
## [param location] 荣耀客户端 Location 编号。
## [param equip_kind] 兼容装备类别。
## [param definition_id] 装备定义标识。
## [param durability] 初始及最大耐久。
## 返回可交给 PlayerStateRecord 解析的字典。
static func _equipment(
	instance_id: String,
	slot_id: String,
	location: int,
	equip_kind: int,
	definition_id: String,
	durability: int,
) -> Dictionary:
	var equipment := EquipmentSlotRecordScript.new().to_dictionary()
	equipment.merge({
		"owner_kind": "vehicle",
		"slot_id": slot_id,
		"slot_location": location,
		"equip_kind": equip_kind,
		"item_instance_id": instance_id,
		"item_definition_id": definition_id,
		"max_durability": durability,
		"durability": durability,
		"upgrade_level": 0,
	}, true)
	return equipment


static func _stack(
	instance_id: String,
	definition_id: String,
	slot_index: int,
	position: Array,
	bound: bool,
	durability: int,
) -> Dictionary:
	var stack := InventoryStackRecordScript.new().to_dictionary()
	stack.merge({
		"stack_id": instance_id,
		"item_definition_id": definition_id,
		"quantity": 1,
		"slot_index": slot_index,
		"container_id": "main",
		"position_px": position,
		"footprint_px": [45, 45],
		"bound": bound,
		"max_durability": durability,
		"durability": durability,
	}, true)
	return stack


## 创建离线调试角色的完整技能成长初始状态。
## 返回技能标识到等级、当前经验和小数余量的映射。
## 设计：离线权威与正式服务器共享相同存档契约，禁止使用仅供 UI 的简化等级表。
static func _initial_skill_states() -> Dictionary:
	var levels := {
		"energy_cannon": 10, "repair": 10, "driving": 10, "mining": 10,
		"cooking": 0, "tailoring": 0, "refining": 0, "manufacturing": 0,
		"processing": 0, "rocket_launcher": 0, "missile": 0, "stealth": 0,
		"radar": 0,
	}
	var states: Dictionary = {}
	for skill_id: String in levels:
		states[skill_id] = {
			"level": levels[skill_id], "current_exp": 0, "fractional_exp": 0.0,
		}
	return states
