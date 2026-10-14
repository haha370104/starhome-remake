extends SceneTree

class World extends AiWorldPort:
	var map_id := "first"
	var opened := 0
	var closed := 0
	var moves := 0
	var attacks := 0
	## 创建供调度器使用的可控角色。
	## [param key] 独立身份。
	## 返回测试会话。
	func open_actor(key: String) -> DomainResult:
		opened += 1
		var actor := AiPlayerActor.new()
		actor.key = key
		return DomainResult.ok(actor)
	## 注入地图变化，检验迟到决策隔离。
	## [param _actor] 当前角色。
	## 返回有限观察。
	func observe(_actor: AiPlayerActor) -> DomainResult:
		var view := AiPlayerObservation.new()
		view.map_id = map_id
		view.health = 100
		view.max_health = 100
		return DomainResult.ok(view)
	## 计数动作，不伪造正式游戏事务的成功证据。
	## [param _actor] 当前角色。[param _target] 目标。
	## 返回调度测试结果。
	func move(_actor: AiPlayerActor, _target: Vector2) -> DomainResult:
		moves += 1
		return DomainResult.ok()
	## 记录有限频率的射击意图。
	## [param _actor] 当前角色。[param _action] 当前行动。[param _target] 当前目标。
	## 返回模拟已接受的意图。
	func perform(_actor: AiPlayerActor, _action: AiPlayerAction, _target: AiPlayerObservation.Target) -> DomainResult:
		attacks += 1
		return DomainResult.ok()
	## 记录会话回收次数。
	## [param _actor] 当前角色。
	## 返回清理结果。
	func close_actor(_actor: AiPlayerActor) -> DomainResult:
		closed += 1
		return DomainResult.ok()

class Provider extends AiDecisionProvider:
	var requests: Array[int] = []
	var cancelled := 0
	## 将请求保持在途，供测试触发超时或迟到结果。
	## [param request_id] 请求号。[param _observation] 当前观察。[param _context] 自身上下文。
	func decide(request_id: int, _observation: Dictionary, _context: Dictionary) -> void:
		requests.append(request_id)
	## 记录主动取消。
	func cancel() -> void:
		cancelled += 1

var checks := 0
var failures: Array[String] = []


## 验证失败重试、频率预算、迟到结果、停止及连续开火的调度边界。
func _initialize() -> void:
	var settings: AiPlayerSettings = AiPlayerSettings.from_dictionary({"actors": [{"id": "test"}],
		"memory_directory": "user://ai-scheduler-%d" % Time.get_ticks_usec(),
		"requests_per_minute": 1, "decision_interval_seconds": 2, "timeout_seconds": 1}).value
	var world := World.new()
	var provider := Provider.new()
	var module := AiPlayerModule.new()
	module.configure(settings, world, provider)
	_check(module.start().is_ok, "启动有限调度")
	var actor := module.actors[0]
	var now := Time.get_ticks_msec()
	module.advance(now)
	module.advance(now + 100)
	_check(provider.requests.size() == 1, "在途请求不重复启动")
	world.map_id = "second"
	provider.completed.emit(1, AiPlayerAction.parse({"kind": "move", "x": 30}))
	_check(actor.action == null and world.moves == 0, "地图变化丢弃迟到决策")
	actor.next_decision = 0
	module.advance(now + 1000)
	_check(provider.requests.size() == 1, "全模块每分钟预算")
	module.advance(now + 61000)
	_check(provider.requests.size() == 2, "窗口到期允许新请求")
	module.advance(now + 64000)
	_check(provider.cancelled == 1 and actor.failures == 1 and actor.pending_request == 0, "无完成信号时看门狗取消")
	for index in 2:
		actor.next_decision = 0
		module.advance(now + 125000 + index * 61000)
		provider.completed.emit(actor.pending_request, DomainResult.failure(&"test.unavailable", "离线"))
	_check(actor.paused and actor.failures == 3, "连续三次失败暂停该角色")
	module.advance(now + 500000)
	_check(provider.requests.size() == 4, "暂停后不再请求")
	module.stop()
	provider.completed.emit(4, AiPlayerAction.parse({"kind": "move", "x": 30}))
	module.stop()
	_check(world.closed == 1 and world.moves == 0 and module.actors.is_empty(), "关闭幂等且旧回调不复活角色")
	module.free()
	var executor := AiPlayerExecutor.new(world)
	var view: AiPlayerObservation = world.observe(actor).value
	view.own_state = {"combat": {"local_weapon_flight": {"energy_cannon.primary": {"range": 300}}}}
	var target := AiPlayerObservation.Target.new()
	target.id = "monster"
	target.position = Vector2(100, 0)
	view.targets["hunt"] = [target]
	executor.begin(actor, AiPlayerAction.parse({"kind": "hunt", "target_id": "monster"}).value, view, 0)
	executor.step(actor, view, 0)
	executor.step(actor, view, 100)
	executor.step(actor, view, 500)
	_check(world.attacks == 2, "连续攻击受本地节流，实际冷却仍归权威端口")
	view.targets.clear()
	_check(executor.step(actor, view, 1000).is_ok, "已攻击目标消失结束当前狩猎")
	print("AI scheduler: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总调度行为断言。
## [param condition] 实际条件。[param message] 预期说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
