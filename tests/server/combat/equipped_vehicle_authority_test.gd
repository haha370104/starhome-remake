extends SceneTree

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const CombatCatalogScript := preload(
	"res://scripts/domain/combat/combat_definition_catalog.gd"
)
const MapInstanceScript := preload("res://scripts/server/authoritative_map_instance.gd")
const CombatModuleScript := preload(
	"res://scripts/server/modules/combat/authoritative_combat_module.gd"
)
const EntityScript := preload("res://scripts/server/authoritative_entity.gd")

var assertions := 0
var failures: PackedStringArray = []


## 验证地图权威战斗实例按玩家实际装配登记撒玛王生命和天神之怒伤害。
func _initialize() -> void:
	var item_catalog: ItemCatalog = ItemCatalogScript.new()
	var item_result := item_catalog.initialize()
	var combat_result := CombatCatalogScript.load_default()
	_expect(item_result.is_ok and combat_result.is_ok, "物品与战斗目录应成功初始化")
	if not item_result.is_ok or not combat_result.is_ok:
		_finish()
		return
	var player := _advanced_player(item_catalog)
	_expect(player != null, "高级战车 Player 聚合应成功构建")
	if player == null:
		_finish()
		return
	var loadout: DomainResult = combat_result.value.vehicle_combat_loadout(
		player,
		20,
		{"base_speed_multiplier": 1500.0, "base_speed_cap": 240.0},
	)
	_expect(loadout.is_ok, "实际固定装配应生成权威战斗定义")
	var combat: AuthoritativeCombatModule = CombatModuleScript.new()
	_expect(combat.configure(20, 17, 1.0).is_ok, "权威战斗状态机应成功初始化")
	var instance: AuthoritativeMapInstance = MapInstanceScript.new()
	instance.instance_id = "authority.equipped.vehicle.test"
	instance.combat_module = combat
	var entity: AuthoritativeEntity = EntityScript.new()
	entity.entity_id = player.entity_id
	entity.map_instance_id = instance.instance_id
	entity.position = Vector2(640, 480)
	instance.entities[player.entity_id] = entity
	var applied: Dictionary = instance.set_vehicle_combat_loadout(player.entity_id, loadout.value)
	_expect(bool(applied.get("ok", false)), "地图实例应登记玩家专属战斗装配")
	var state := instance.vehicle_combat_state_for(player.entity_id)
	_expect(state != null and state.max_health == 13000,
		"权威战车最大生命不得回退到新兵 70")
	var actor: Dictionary = combat.actors.get(player.entity_id, {})
	var weapons: Dictionary = actor.get("weapons", {})
	var primary: Dictionary = weapons.get("energy_cannon.primary", {})
	_expect(String(primary.get("weapon_id", "")) == "glory_equipment_gun1000_c4c24e2500",
		"权威主炮身份必须是天神之怒")
	_expect(int(primary.get("minimum_damage", 0)) == 900,
		"权威基础伤害不得回退到新兵能量炮 7")
	_expect(weapons.size() == 1, "空副武器槽不得获得两件新手武器的攻击能力")
	for definition_id: String in ["glory_equipment_missile4_9861000063", "glory_equipment_missile5_15584171c6", "official_rocket_firegun_6"]:
		var secondary: VehicleWeapon = item_catalog.create(definition_id, {"instance_id": definition_id}).value
		player.vehicle.loadout.equip(secondary, 13, player.vehicle.loadout.revision)
		var updated: DomainResult = combat_result.value.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500.0, "base_speed_cap": 240.0})
		_expect(updated.is_ok, "实际副武器可以参与装配计算")
		var ability_id := secondary.combat_mode() + ".primary"
		var actual: Dictionary = updated.value.weapons[ability_id]
		_expect(updated.value.weapons.size() == 2 and actual.weapon_id == definition_id, "仅登记实际安装的副武器")
		_expect(actual.minimum_damage == secondary.base_attack and actual.working_energy_cost == secondary.working_energy_per_shot, "副武器伤害与能耗来自装备")
		if secondary.combat_mode() == "missile":
			_expect(is_equal_approx(actual.projectile_speed, 250.0), "所有导弹型号共享原引擎换算后的250像素/秒")
		var stat_key := "missile_attack" if secondary.combat_mode() == "missile" else "rocket_attack"
		_expect(player.calculate_vehicle_stats()[stat_key] == secondary.base_attack, "战车面板包含副武器基础攻击")
	_finish()


## 构建装备撒玛王底盘、天神之怒和初级引擎的测试玩家。
## [param catalog] 已初始化的统一物品目录。
## 返回完整 Player；任一固定装备恢复失败时返回 null。
func _advanced_player(catalog: ItemCatalog) -> Player:
	var player := Player.new({
		"character_id": "player.advanced.authority",
		"display_name": "高级战车测试",
		"skills": {"driving": {"level": 10, "current_exp": 0, "fractional_exp": 0.0}},
		"vehicle": {
			"vehicle_id": "vehicle.advanced.authority",
			"definition_id": "recruit_tank",
			"max_health": 70,
			"health": 70,
			"reserve_energy_capacity": 10000.0,
			"reserve_energy": 10000.0,
			"working_energy_capacity": 100.0,
			"working_energy": 100.0,
			"output_power": 21.0,
		},
	})
	for definition_id: String in [
		"glory_equipment_tank1000_27ae5e8059",
		"glory_equipment_gun1000_c4c24e2500",
		"beginner_engine",
	]:
		var created := catalog.create(definition_id, {
			"instance_id": "authority.%s" % definition_id,
			"footprint_px": [45, 45],
		})
		if not created.is_ok or not player.vehicle.loadout.restore(created.value).is_ok:
			return null
	player.vehicle.reconcile_loadout_state()
	return player


## 记录一项测试断言。
## [param condition] 预期成立的条件。
## [param message] 失败时输出的中文原因。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 汇总测试结果并退出独立进程。
func _finish() -> void:
	if failures.is_empty():
		print("EQUIPPED_VEHICLE_AUTHORITY_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
