class_name OfflinePlayerPanelAuthority
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")
const PanelServiceScript := preload("res://scripts/server/player_panels/authoritative_player_panel_service.gd")

var _service: AuthoritativePlayerPanelService
var _state: PlayerStateRecord


## 创建仅用于显式离线调试的内存权威状态。
## 返回初始化成功的桥接器或目录/聚合错误。
## 设计：正式联机永不调用本桥接器；它复用服务端领域服务以保证调试 UI 行为一致。
func initialize() -> DomainResult:
	_service = PanelServiceScript.new()
	var service_result := _service.initialize()
	if not service_result.is_ok:
		return service_result
	var state_result = PlayerStateRecordScript.from_dictionary({
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
		"character_faction": "易安港",
		"character_residence": "基地大厅一层",
		"character_description": "荣耀版复刻工程的离线调试角色。",
		"inventory_stacks": [{
			"stack_id": "inventory.spare_engine",
			"item_definition_id": "beginner_engine",
			"quantity": 1,
			"slot_index": 0,
			"container_id": "main",
			"position_px": [0, 0],
			"footprint_px": [45, 45],
			"locked": false,
			"bound": false,
			"max_durability": 900,
			"durability": 900,
		}, {
			"stack_id": "inventory.training_shirt",
			"item_definition_id": "male_sleeveless_shirt",
			"quantity": 1,
			"slot_index": 1,
			"container_id": "main",
			"position_px": [60, 0],
			"footprint_px": [45, 45],
			"locked": false,
			"bound": true,
			"max_durability": 64,
			"durability": 64,
		}],
		"equipment_slots": [
			_equipment("equipment.chassis", "chassis", 0, 0, "recruit_tank", 1020),
			_equipment("equipment.weapon", "primary_weapon", 1, 1, "recruit_energy_cannon", 900),
			_equipment("equipment.engine", "propulsion", 3, 3, "beginner_engine", 900),
		],
		"character_max_health": 100,
		"character_health": 100,
		"character_experience": 0,
		"character_skills": {
			"energy_cannon": 10,
			"repair": 10,
			"driving": 10,
			"mining": 10,
			"cooking": 0,
			"tailoring": 0,
			"refining": 0,
			"manufacturing": 0,
			"rocket_launcher": 0,
			"missile": 0,
			"stealth": 0,
			"radar": 0,
		},
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
		"map_instance_id": "offline.instance.1",
		"position": [720.0, 540.0],
		"facing_direction": 6,
		"checkpoint_id": "offline.debug",
	})
	if not state_result.is_ok:
		return state_result
	_state = state_result.value
	return DomainResult.ok(self)


## 执行离线调试面板命令并返回与服务器相同的 panel_bundle。
## [param command] 面板查询或事务意图。
## 返回成功快照或领域拒绝。
func execute(command: Dictionary) -> DomainResult:
	if _service == null or _state == null:
		return DomainResult.failure(&"panels.offline_unavailable", "offline panel authority is unavailable")
	var result := _service.execute(_state, command)
	if not result.is_ok:
		return result
	var value: Dictionary = result.value
	if bool(value.get("changed", false)):
		_state = value["candidate"]
		_state.revision += 1
	return DomainResult.ok(_service.build_bundle(_state))


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
	return {
		"owner_kind": "vehicle",
		"slot_id": slot_id,
		"slot_location": location,
		"equip_kind": equip_kind,
		"item_instance_id": instance_id,
		"item_definition_id": definition_id,
		"max_durability": durability,
		"durability": durability,
		"upgrade_level": 0,
	}
