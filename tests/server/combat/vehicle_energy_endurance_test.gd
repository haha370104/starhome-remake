extends SceneTree

const MERCHANT_PATH := "res://data/gameplay/commerce/weapon_merchant_v1.json"
const MAP_ID := "energy.endurance.test"
const ACTOR_ID := "player.energy.endurance"
const ABILITY_ID := "energy_cannon.primary"
const HZ := 20
const MINIMUM_BURST_SECONDS := 4.5

var assertions := 0
var failures: PackedStringArray = []


## 通过真实目录、装配、地图模拟与攻击意图验证在售各档车炮的连续输出窗口。
## 设计：测试只创建内存玩家，不读取或写入日常账号存档。
func _initialize() -> void:
	var items := ItemCatalog.new()
	var item_result := items.initialize()
	var combat_result := CombatDefinitionCatalog.load_default()
	_expect(item_result.is_ok and combat_result.is_ok, "正式装备和战斗目录能够加载")
	if not item_result.is_ok or not combat_result.is_ok:
		_finish()
		return
	var catalog: CombatDefinitionCatalog = combat_result.value
	var merchant: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MERCHANT_PATH))
	var offered: Dictionary = merchant.merchant.official_whitelist_ids
	var chassis_ids: Array = offered.vehicle_chassis
	var cannon_ids: Array = offered.energy_cannon
	var engine_ids: Array = offered.vehicle_engine
	_expect(chassis_ids.size() == cannon_ids.size() and chassis_ids.size() == engine_ids.size(),
		"车、炮、引擎的在售档位一一对应；新增档位必须同时检查配套")
	if chassis_ids.size() != cannon_ids.size() or chassis_ids.size() != engine_ids.size():
		_finish()
		return
	for index: int in range(chassis_ids.size()):
		var loadout := _loadout(items, catalog, chassis_ids[index], cannon_ids[index], engine_ids[index])
		if loadout.is_empty():
			continue
		var label := String(items.definition(chassis_ids[index]).display_name)
		var normal := _first_energy_failure(loadout, 1)
		var rapid := _first_energy_failure(loadout, 6)
		_expect(normal.x >= MINIMUM_BURST_SECONDS, "%s 满能量最高射速至少连续输出四五秒" % label)
		_expect(normal == rapid, "%s 高频重复点击不会缩短连射窗口或重复扣能量" % label)
		print("ENERGY_ENDURANCE %s | first_refusal=%.2fs | shots=%d" % [label, normal.x, int(normal.y)])
		if index == chassis_ids.size() - 1:
			_test_conqueror_resources(loadout)
			_test_chassis_swap(items, catalog, loadout)
	_finish()


## 从正式装备目录恢复没有强化、食品或人物装备增益的车炮引擎组合。
## [param items] 已初始化的物品目录。
## [param catalog] 正式权威战斗目录。
## [param chassis_id] 被测底盘定义。
## [param cannon_id] 同档能量炮定义。
## [param engine_id] 同档引擎定义。
## 返回正式装配定义；初始化失败返回空字典并记录断言。
func _loadout(items: ItemCatalog, catalog: CombatDefinitionCatalog,
	chassis_id: String, cannon_id: String, engine_id: String) -> Dictionary:
	var player := Player.new({"character_id": ACTOR_ID,
		"skills": {"driving": {"level": 1000, "current_exp": 0}}})
	for id: String in [chassis_id, cannon_id, engine_id]:
		var created := items.create(id, {"instance_id": "energy." + id})
		_expect(created.is_ok, "测试装备可以实例化：" + id)
		if not created.is_ok:
			return {}
		var restored := player.vehicle.loadout.restore(created.value)
		_expect(restored.is_ok, "测试装备可以进入固定槽：" + id)
		if not restored.is_ok:
			return {}
	player.vehicle.reconcile_loadout_state()
	var result := catalog.vehicle_combat_loadout(player, HZ,
		{"base_speed_multiplier": 1500.0, "base_speed_cap": 240.0})
	_expect(result.is_ok, "完整装配可以生成权威战斗定义")
	return result.value if result.is_ok else {}


## 将目录装配交给真实地图的登记入口，保留权威冷却与资源所有者。
## [param loadout] 已验证的真实玩家装配。
## 返回不含怪物、网络及持久化服务的隔离地图。
func _instance(loadout: Dictionary) -> AuthoritativeMapInstance:
	var instance := AuthoritativeMapInstance.new()
	instance.instance_id = MAP_ID
	instance.combat_module = AuthoritativeCombatModule.new()
	_expect(instance.combat_module.configure(HZ, 17).is_ok, "初始化权威能量恢复时钟")
	var entity := AuthoritativeEntity.new()
	entity.entity_id = ACTOR_ID
	entity.map_instance_id = MAP_ID
	instance.entities[ACTOR_ID] = entity
	_expect(instance.set_vehicle_combat_loadout(ACTOR_ID, loadout).ok, "地图按实际装备登记战车")
	return instance


## 持续提交攻击直至首次缺能量，冷却期间的重复点击必须保持能量不变。
## [param loadout] 被测真实装备的权威装配。
## [param clicks_per_tick] 每个模拟刻提交的点击次数。
## [param reserve_energy] 非负时模拟指定储备量，负数保持满储备。
## 返回首次能量拒绝的秒数与此前成功发射数；60 秒内不拒绝时以 60 秒截断。
func _first_energy_failure(loadout: Dictionary, clicks_per_tick: int, reserve_energy := -1.0) -> Vector2:
	var instance := _instance(loadout)
	var state := instance.vehicle_combat_state_for(ACTOR_ID)
	if reserve_energy >= 0.0:
		state.reserve_energy = reserve_energy
	var shots := 0
	var sequence := 0
	for tick: int in range(60 * HZ):
		for click: int in range(clicks_per_tick):
			sequence += 1
			var before := state.working_energy
			var result := _fire(instance, sequence)
			if result.is_ok:
				shots += 1
			else:
				_expect(is_equal_approx(before, state.working_energy), "失败或冷却中的点击不扣工作能量")
				if result.error_code == &"combat.insufficient_working_energy":
					return Vector2(float(tick) / HZ, shots)
				_expect(result.error_code == &"combat.weapon_cooldown", "连续点击只允许被冷却或能量拒绝：" + String(result.error_code))
		instance.simulate(1.0 / HZ)
	return Vector2(60.0, shots)


## 检查征服者五秒资源收支、储备转换以及空储备导致的输出缩短。
## [param loadout] 征服者与虎式突袭炮的正式装配。
func _test_conqueror_resources(loadout: Dictionary) -> void:
	var instance := _instance(loadout)
	var state := instance.vehicle_combat_state_for(ACTOR_ID)
	_expect(is_equal_approx(state.working_energy_capacity, 450.0), "征服者使用450容量，不残留新兵100容量")
	var initial_reserve := state.reserve_energy
	for tick: int in range(5 * HZ):
		_fire(instance, tick + 1)
		instance.simulate(1.0 / HZ)
	_expect(is_equal_approx(state.working_energy, 150.0), "最高频率五秒13发后还剩150工作能量")
	_expect(is_equal_approx(initial_reserve - state.reserve_energy, 350.0), "五秒恢复350工作能量并等量消耗储备")
	var empty_reserve := _first_energy_failure(loadout, 1, 0.0)
	_expect(is_equal_approx(empty_reserve.x, 3.6) and int(empty_reserve.y) == 9,
		"储备耗尽后只有九发，3.6秒拒绝；不能误认为恢复倍率或容量失效")
	var almost_empty := _first_energy_failure(loadout, 1, 100.0)
	_expect(almost_empty.x > empty_reserve.x and almost_empty.x < 7.6,
		"储备在战斗中耗尽会缩短连射窗口")
	state.working_energy = 0.0
	state.reserve_energy = 0.0
	instance.simulate(1.0 / HZ)
	_expect(is_zero_approx(state.working_energy), "空储备不得凭空恢复工作能量")
	state.reserve_energy = 100.0
	instance.simulate(1.0 / HZ)
	_expect(is_equal_approx(state.working_energy, 3.5), "补充储备后下一刻恢复工作能量")


## 验证换车保留资源比例，满能量新兵换征服者不会仍只有100点。
## [param items] 实际物品目录。
## [param catalog] 实际战斗目录。
## [param conqueror] 征服者目标装配。
func _test_chassis_swap(items: ItemCatalog, catalog: CombatDefinitionCatalog, conqueror: Dictionary) -> void:
	var starter := _loadout(items, catalog, "glory_equipment_tank1_c2ba1ac5af",
		"glory_equipment_gun1_216568dc50", "glory_equipment_engine1_8030b9773a")
	var instance := _instance(starter)
	_expect(instance.set_vehicle_combat_loadout(ACTOR_ID, conqueror).ok, "满能量换装征服者成功")
	_expect(is_equal_approx(instance.vehicle_combat_state_for(ACTOR_ID).working_energy, 450.0),
		"满能量换车得到450/450工作能量")
	instance.set_vehicle_combat_loadout(ACTOR_ID, starter)
	instance.vehicle_combat_state_for(ACTOR_ID).working_energy = 50.0
	instance.set_vehicle_combat_loadout(ACTOR_ID, conqueror)
	_expect(is_equal_approx(instance.vehicle_combat_state_for(ACTOR_ID).working_energy, 225.0),
		"半能量换车保持半能量，不通过换装补满")


## 按网络契约提交一次不携带资源数值的主炮攻击。
## [param instance] 持有玩家战斗状态的隔离地图。
## [param sequence] 单调递增的命令序号。
## 返回正式权威模块的处理结果。
func _fire(instance: AuthoritativeMapInstance, sequence: int) -> DomainResult:
	var intent := UseAbilityIntent.new(MAP_ID, ABILITY_ID, Vector2(180, 0), sequence)
	return instance.combat_module.handle_weapon_attack(ACTOR_ID, intent.to_dictionary())


## 记录验收条件，失败信息随测试结束统一输出。
## [param condition] 应当成立的资源或交互条件。
## [param message] 失败时的具体原因。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition and message not in failures:
		failures.append(message)


## 输出检查标记并使用退出码表明验收结果。
func _finish() -> void:
	if failures.is_empty():
		print("VEHICLE_ENERGY_ENDURANCE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
