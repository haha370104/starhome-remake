extends SceneTree

const MapInstanceScript := preload("res://scripts/server/authoritative_map_instance.gd")
const CombatCatalogScript := preload("res://scripts/domain/combat/combat_definition_catalog.gd")
const MoveIntentContract := preload("res://scripts/network/contracts/move_intent.gd")
const PLAYER_ID := "player.d04.test"
const MAP_PATH := "res://data/maps/d04_field_zone.json"
const CHARACTER_MAP_PATH := "res://data/maps/yian_harbor_hall_floor_1.json"

var failures: Array[String] = []
var assertions := 0


## 使用正式地图实例运行 D04 战斗纵切测试，不再依赖客户端离线桥。
func _initialize() -> void:
	var instance: AuthoritativeMapInstance = MapInstanceScript.new()
	var loaded := instance.load_map(MAP_PATH)
	_expect(bool(loaded.get("ok", false)), "D04 正式地图实例应加载地图与导航")
	var spawned := instance.spawn_entity(PLAYER_ID, Vector2(2412, 2400), 203.0)
	_expect(bool(spawned.get("ok", false)), "D04 正式地图实例应接纳测试玩家")
	var catalog_result = CombatCatalogScript.load_default()
	_expect(catalog_result.is_ok, "正式战斗目录应加载")
	if not bool(loaded.get("ok", false)) or not bool(spawned.get("ok", false)) \
			or not catalog_result.is_ok:
		_finish()
		return
	var configured := instance.configure_combat(catalog_result.value, 20)
	_expect(bool(configured.get("ok", false)), "D04 战斗应由正式地图实例配置")
	if bool(configured.get("ok", false)):
		_test_population_and_routes(instance)
		_test_driving_progression_scope(instance, catalog_result.value)
		_test_authoritative_player_attack(instance)
		_test_zero_attack_is_not_invented(instance)
	_finish()


## 验证只有战车形态的权威有效位移会产生驾驶经验，人物步行不产生任何经验。
## [param vehicle_instance] 已加载并配置战斗的 D04 战车地图实例。
## [param combat_catalog] 服务端用于给人物地图装配相同战车状态的战斗目录。
## 设计：故意让两张地图都持有战车装配，证明经验边界取决于地图人物表现而非装配是否存在。
func _test_driving_progression_scope(vehicle_instance: AuthoritativeMapInstance, combat_catalog) -> void:
	var vehicle_entity: AuthoritativeEntity = vehicle_instance.entities[PLAYER_ID]
	var vehicle_target: Vector2 = vehicle_instance.navigation.closest_reachable_position(
		vehicle_entity.position,
		vehicle_entity.position + Vector2(192, 0),
	)
	var vehicle_move := vehicle_instance.handle_move_intent(
		PLAYER_ID,
		MoveIntentContract.new(vehicle_instance.instance_id, vehicle_target, 10).to_dictionary(),
	)
	_expect(vehicle_move.ok, "D04 战车移动夹具必须被权威导航接受")
	vehicle_instance.simulate(0.5)
	var vehicle_events := vehicle_instance.drain_skill_progression_events()
	_expect(vehicle_events.any(func(event: Dictionary) -> bool:
		return String(event.get("source", "")) == "accepted_driving_movement" \
			and String(event.get("skill_id", "")) == "driving" \
			and float(event.get("distance", 0.0)) > 0.0
	), "战车在野外的权威有效位移必须产生驾驶经验事件")

	var character_instance: AuthoritativeMapInstance = MapInstanceScript.new()
	var loaded := character_instance.load_map(CHARACTER_MAP_PATH)
	_expect(loaded.ok, "人物步行经验夹具必须加载基地大厅")
	if not loaded.ok:
		return
	var configured := character_instance.configure_combat(combat_catalog, 20)
	_expect(configured.ok, "人物地图必须配置与正式服务器相同的战车资源状态")
	var spawned := character_instance.spawn_entity("player.walking.test", Vector2(730, 1330), 203.0)
	_expect(spawned.ok, "人物步行经验夹具必须生成玩家")
	if not configured.ok or not spawned.ok:
		return
	var character_entity: AuthoritativeEntity = spawned.value
	var character_before := character_entity.position
	var character_target: Vector2 = character_instance.navigation.closest_reachable_position(
		character_entity.position,
		character_entity.position + Vector2(192, 0),
	)
	var character_move := character_instance.handle_move_intent(
		character_entity.entity_id,
		MoveIntentContract.new(
			character_instance.instance_id,
			character_target,
			1,
		).to_dictionary(),
	)
	_expect(character_move.ok, "基地大厅人物移动夹具必须被权威导航接受")
	character_instance.simulate(0.5)
	_expect(
		character_entity.position.distance_to(character_before) > 0.0,
		"人物必须实际完成位移后再验证零经验",
	)
	_expect(
		character_instance.drain_skill_progression_events().is_empty(),
		"非战斗地图的人物步行不得产生驾驶或其他技能经验事件",
	)


## 验证 D04 配置化种群、资源和正式地图 AStar 游荡路线。
## [param instance] 已加载 D04 并配置战斗的正式地图实例。
func _test_population_and_routes(instance: AuthoritativeMapInstance) -> void:
	var module: AuthoritativeCombatModule = instance.combat_module
	var snapshot := module.snapshot_for_actor(PLAYER_ID)
	_expect(snapshot.monsters.size() == 200, "D04 应初始化配置上限的二百只怪物")
	var species: Dictionary = {}
	for monster: Dictionary in snapshot.monsters:
		species[String(monster.species_id)] = int(species.get(String(monster.species_id), 0)) + 1
	_expect(species == {
		"om_adult": 50, "om_larva": 50, "photosensitive_orb": 50, "toxic_gel": 50,
	}, "D04 怪物数量应完全由地图配置驱动")
	_expect(snapshot.local_vehicle.health == 70 and snapshot.local_vehicle.max_health == 70,
		"新兵底盘应拥有七十点生命")
	_expect(is_equal_approx(snapshot.local_vehicle.working_energy, 100.0) \
		and is_equal_approx(snapshot.local_vehicle.working_energy_capacity, 100.0),
		"新兵战车应公开一百点当前工作能量")
	var first_id: String = snapshot.monsters[0].entity_id
	var first_monster: MonsterLifecycle = module.monster_for(first_id)
	var first_position := first_monster.position
	module.advance_ticks(99)
	_expect(first_monster.position.is_equal_approx(first_position),
		"未交战怪物应先等待配置的五秒间隔")
	module.advance_ticks(2)
	_expect(not first_monster.position.is_equal_approx(first_position),
		"未交战怪物应在五秒后开始一次确定性游荡")
	var first_roaming_position := first_monster.position
	module.advance_ticks(3)
	_expect(first_monster.action == &"move" \
		and not first_monster.position.is_equal_approx(first_roaming_position),
		"D04 怪物开始游荡后必须连续推进，不能每五秒只抽动一帧")
	_expect(first_monster.movement_route.size() >= 2,
		"怪物游荡必须持有正式地图实例生成的完整 AStar 路线")


## 验证玩家攻击、能量消耗和技能成长事件均由正式地图实例结算。
## [param instance] 已加载 D04 并配置战斗的正式地图实例。
func _test_authoritative_player_attack(instance: AuthoritativeMapInstance) -> void:
	var module: AuthoritativeCombatModule = instance.combat_module
	var target_id: String = module.monster_ids()[0]
	var target: MonsterLifecycle = module.monster_for(target_id)
	var player_position: Vector2 = instance.navigation.closest_reachable_position(
		target.position, target.position + Vector2(100, 0)
	)
	_expect(player_position.is_finite(), "目标附近应存在测试玩家可用的可达脚点")
	if not player_position.is_finite():
		return
	var entity: AuthoritativeEntity = instance.entities[PLAYER_ID]
	entity.position = player_position
	entity.target_position = player_position
	module.update_actor_position(PLAYER_ID, player_position)
	var before_health := target.health
	var result: Dictionary = instance.handle_use_ability(PLAYER_ID, {
		"map_instance_id": instance.instance_id,
		"ability_id": "energy_cannon.primary",
		"aim_world_position": {"x": target.position.x, "y": target.position.y},
		"input_sequence": 1,
	})
	_expect(bool(result.get("ok", false)), "附近怪物应接受只含坐标的能量炮攻击意图")
	if not bool(result.get("ok", false)):
		return
	_expect(target.health == before_health, "炮弹抵达前不得提前扣除怪物生命")
	var vehicle = module.vehicle_state_for(PLAYER_ID)
	_expect(is_equal_approx(vehicle.working_energy, 90.0), "成功发射应立即消耗十点工作能量")
	var impact_tick := int(result.value["impact_tick"])
	module.advance_ticks(impact_tick - module.current_tick)
	_expect(target.health == before_health - 7, "新兵能量炮命中后应造成目录基础攻击七点")
	var progression_events := instance.drain_skill_progression_events()
	_expect(progression_events.any(func(event: Dictionary) -> bool:
		return String(event.get("skill_id", "")) == "energy_cannon" \
			and int(event.get("damage", 0)) == 7
	), "最终有效伤害应由正式地图实例生成能量炮成长事件")


## 验证未知持续腐蚀规则不会为零攻击毒胶捏造伤害。
## [param instance] 已加载 D04 并配置战斗的正式地图实例。
func _test_zero_attack_is_not_invented(instance: AuthoritativeMapInstance) -> void:
	var toxic_id := ""
	for monster_id: String in instance.combat_module.monster_ids():
		if instance.combat_module.monster_for(monster_id).species_id == "toxic_gel":
			toxic_id = monster_id
			break
	_expect(not toxic_id.is_empty(), "D04 应生成毒胶运行时实例")
	if not toxic_id.is_empty():
		_expect(instance.combat_module.monster_for(toxic_id).attack_mode.base_attack == 0,
			"未确认腐蚀公式前不得覆盖毒胶已恢复的零基础攻击")


## 记录一个布尔断言。
## [param condition] 预期成立的条件。
## [param message] 失败时输出的信息。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 汇总断言并退出独立测试进程。
func _finish() -> void:
	if failures.is_empty():
		print("D04_AUTHORITATIVE_COMBAT_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
