extends SceneTree

const POPULATION := 200
var failures: Array[String] = []
var assertions := 0


## 验证初始种群、补怪、重复停顿与重生各自分散游荡时刻。
func _initialize() -> void:
	_test_population_timing()
	_test_late_population()
	_test_route_distribution()
	if failures.is_empty():
		print("MONSTER_WANDER_TIMING_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 检查每只怪物独立且可复现的计时，不消耗战斗伤害与掉落的随机序列。
func _test_population_timing() -> void:
	var module := _population()
	var replay := _population(true)
	var initial_ticks: Dictionary = {}
	var pause_ticks: Dictionary = {}
	var varied_monsters := 0
	var combat_random_state: int = module._random.state
	for monster: MonsterLifecycle in module.monsters.values():
		_expect(monster.next_wander_tick >= 1 and monster.next_wander_tick <= 100,
			"首次游荡须分布在出生后第1～100 tick")
		initial_ticks[monster.next_wander_tick] = true
		var twin: MonsterLifecycle = replay.monster_for(monster.monster_id)
		_expect(twin.next_wander_tick == monster.next_wander_tick,
			"计时须由怪物身份独立决定，不受注册顺序影响")
		var own_delays: Dictionary = {}
		for round_index in range(10):
			var now := 1000 + round_index * 200
			monster.pause_wander(now)
			twin.pause_wander(now)
			var delay := monster.next_wander_tick - now
			_expect(delay >= 75 and delay <= 125, "后续停顿须在配置间隔的75%～125%范围")
			_expect(twin.next_wander_tick == monster.next_wander_tick, "相同输入须重现每轮停顿")
			own_delays[delay] = true
			pause_ticks[delay] = true
		if own_delays.size() > 1:
			varied_monsters += 1
	_expect(initial_ticks.size() >= 50, "200只怪物不能集中在少数初始 tick 启动")
	_expect(pause_ticks.size() >= 30 and varied_monsters == POPULATION,
		"后续等待须持续错开，不能只是每只怪物固定一个偏移")
	_expect(module._random.state == combat_random_state, "游荡计时不能消耗伤害与掉落随机序列")
	module = _population()
	for monster: MonsterLifecycle in module.monsters.values():
		monster.apply_damage(monster.health, "fixture", module.current_tick)
	module.advance_ticks(20, false)
	var respawn_ticks: Dictionary = {}
	for monster: MonsterLifecycle in module.monsters.values():
		_expect(monster.is_alive(), "同批死亡怪物须按原重生时间恢复")
		var delay := monster.next_wander_tick - module.current_tick
		_expect(delay >= 75 and delay <= 125, "重生等待也须遵循分散间隔")
		respawn_ticks[monster.next_wander_tick] = true
	_expect(respawn_ticks.size() >= 30, "同批重生不得覆盖回统一游荡时间")


## 验证运行中的新增种群以实际注册时钟起算，而非把初始延迟误当绝对时刻。
func _test_late_population() -> void:
	var module := AuthoritativeCombatModule.new()
	module.configure(20, 7)
	module.advance_ticks(1200)
	var deadlines: Dictionary = {}
	for index in range(POPULATION):
		var registered := module.register_monster(_definition(index))
		_expect(registered.is_ok, "运行中补怪应能登记")
		var monster: MonsterLifecycle = registered.value
		var delay := monster.next_wander_tick - module.current_tick
		_expect(delay >= 1 and delay <= 100, "补怪须从当前时钟开始等待，不能立刻全部寻路")
		deadlines[monster.next_wander_tick] = true
	_expect(deadlines.size() >= 50, "同批补怪也须分散初始等待")


## 使用真实 AI 调度与失败导航夹具统计各 tick 的请求，覆盖持续失败的重试退避。
func _test_route_distribution() -> void:
	var module := _population()
	var calls := [0]
	var per_monster: Dictionary = {}
	module.set_monster_route_resolver(func(id: String, _start: Vector2, _target: Vector2) -> Dictionary:
		calls[0] += 1
		per_monster[id] = int(per_monster.get(id, 0)) + 1
		return {}
	)
	var peak := 0
	var active_ticks := 0
	for tick in range(1000):
		calls[0] = 0
		module.advance_ticks(1)
		peak = maxi(peak, calls[0])
		if calls[0] > 0:
			active_ticks += 1
	_expect(peak <= 12, "固定200只怪物夹具不能在一帧集中请求导航，实际峰值%d" % peak)
	_expect(active_ticks >= 500, "请求须分散到持续运行的多数 tick")
	_expect(per_monster.size() == POPULATION, "所有怪物都须获得游荡机会")
	for count: int in per_monster.values():
		_expect(count >= 7, "失败重试不能造成怪物永久停留")
	print("WANDER_DISTRIBUTION population=%d ticks=1000 peak=%d active_ticks=%d" % [
		POPULATION, peak, active_ticks])


## 创建固定身份的200只同种怪物，支持倒序注册以排除全局随机数依赖。
## [param reverse_order] 是否按相反顺序登记。
## 返回无网络、无持久化的战斗模块。
func _population(reverse_order := false) -> AuthoritativeCombatModule:
	var module := AuthoritativeCombatModule.new()
	module.configure(20, 7)
	for offset in range(POPULATION):
		var index := POPULATION - 1 - offset if reverse_order else offset
		_expect(module.register_monster(_definition(index)).is_ok, "种群应能登记")
	return module


## 构造只游荡、不主动攻击的同批怪物配置。
## [param index] 稳定实例编号。
## 返回权威怪物生成定义。
func _definition(index: int) -> Dictionary:
	return {"monster_id": "wander.%d" % index, "map_instance_id": "wander.fixture",
		"position": Vector2(index * 200.0, 0), "max_health": 30, "respawn_seconds": 1.0,
		"runtime_move_speed": 60.0, "wander_radius": 80.0, "wander_interval_seconds": 5.0}


## 记录测试断言。
## [param condition] 需要成立的条件。
## [param message] 失败时的诊断说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition and message not in failures:
		failures.append(message)
