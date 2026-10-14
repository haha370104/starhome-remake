class_name AiPlayerModule
extends Node

var actors: Array[AiPlayerActor] = []
var request_count := 0
var running := false
var _settings: AiPlayerSettings
var _world: AiWorldPort
var _provider: AiDecisionProvider
var _executor: AiPlayerExecutor
var _memory := AiPlayerMemory.new()
var _requests: Array[int] = []
var _pending_actor: AiPlayerActor
var _pending_view: AiPlayerObservation
var _pending_deadline := 0
var _feedback: Dictionary = {}
var _elapsed := 0.0
var _cursor := 0


## 装配依赖但不创建角色；启动由场景树就绪阶段显式触发。
## [param settings] 有限预算配置。[param world] 权威端口。[param provider] 异步决策提供器。
func configure(settings: AiPlayerSettings, world: AiWorldPort, provider: AiDecisionProvider) -> void:
	_settings = settings
	_world = world
	_provider = provider
	_executor = AiPlayerExecutor.new(world)
	add_child(provider)
	provider.completed.connect(_on_decision)


## 场景树完成初始化后再启动，避免影响正常服务器构造顺序。
func _ready() -> void:
	call_deferred("start")


## 启动独立角色与记忆；失败回滚本模块已创建的会话。
## 返回启动结果，失败不向普通登录传播。
func start() -> DomainResult:
	if running: return DomainResult.ok()
	if not _memory.start(_settings.memory_directory): return DomainResult.failure(&"ai.memory_start", "AI记忆线程无法启动")
	running = true
	for spec: AiPlayerSettings.ActorSpec in _settings.actors:
		var opened := _world.open_actor(spec.id)
		if not opened.is_ok:
			stop()
			push_warning("可选AI未启动：" + String(opened.error_code))
			return opened
		var actor: AiPlayerActor = opened.value
		actor.goal = spec.goal
		actor.next_decision = Time.get_ticks_msec() + actors.size() * 1000
		_memory.restore(actor)
		actors.append(actor)
	print("Optional AI players started: provider=%s actors=%d" % [_settings.provider, actors.size()])
	return DomainResult.ok()


## 每四分之一秒执行一次有界调度；模块关闭后不推进任何逻辑。
## [param delta] 帧间隔。
func _process(delta: float) -> void:
	if not running: return
	_elapsed += delta
	if _elapsed < 0.25: return
	_elapsed = 0.0
	advance(Time.get_ticks_msec())


## 公平轮转角色并实施全模块预算；不在模拟循环等待模型或磁盘。
## [param now] 可注入的单调毫秒时钟。
func advance(now: int) -> void:
	if not running or actors.is_empty(): return
	while not _requests.is_empty() and now - _requests[0] >= 60000: _requests.pop_front()
	if _pending_actor != null and now >= _pending_deadline:
		_provider.cancel()
		_on_decision(_pending_actor.pending_request, DomainResult.failure(&"ai.decision_timeout", "AI决策超时"))
	# 每次最多观察一个角色，八角色也不会在同一帧生成八份快照。
	var actor := actors[_cursor % actors.size()]
	_cursor += 1
	if actor.paused or actor.pending_request != 0: return
	if actor.action == null and now < actor.next_decision: return
	var observed := _world.observe(actor)
	if not observed.is_ok:
		actor.paused = true
		_record(actor, observed, now)
		return
	var view: AiPlayerObservation = observed.value
	if actor.action != null:
		var result := _executor.step(actor, view, now)
		if result != null: _finish(actor, result, now)
		return
	if request_count >= _settings.max_requests_per_session:
		actor.paused = true
		_record(actor, DomainResult.failure(&"ai.budget_exhausted", "AI本次运行决策预算已用完"), now)
		return
	if _pending_actor != null or _requests.size() >= _settings.requests_per_minute: return
	request_count += 1
	_requests.append(now)
	actor.pending_request = request_count
	_pending_actor = actor
	_pending_view = view
	_pending_deadline = now + int((_settings.timeout_seconds + 1) * 1000)
	_provider.decide(request_count, view.to_dictionary(), {"actor": actor.key, "goal": actor.goal,
		"memory": actor.memory, "history": actor.history.duplicate(true), "last_result": _feedback.get(actor.key, {})})


## 检查请求代次和实时地图，迟到决策不得复活已关闭角色。
## [param request_id] 提供器返回的请求号。[param result] 已解析行动或失败。
func _on_decision(request_id: int, result: DomainResult) -> void:
	if not running or _pending_actor == null or request_id != _pending_actor.pending_request: return
	var actor := _pending_actor
	var decision_map := _pending_view.map_id
	_pending_actor = null
	_pending_view = null
	actor.pending_request = 0
	var now := Time.get_ticks_msec()
	if not result.is_ok or not result.value is AiPlayerAction:
		actor.failures += 1
		actor.next_decision = now + int(_settings.decision_interval_seconds * 1000) * actor.failures
		actor.paused = actor.failures >= 3
		_record(actor, result if not result.is_ok else DomainResult.failure(&"ai.invalid_action", "AI提供器返回了非法类型"), now)
		return
	var observed := _world.observe(actor)
	if not observed.is_ok or observed.value.map_id != decision_map:
		actor.next_decision = now + int(_settings.decision_interval_seconds * 1000)
		_record(actor, DomainResult.failure(&"ai.stale_decision", "决策期间地图变化，已丢弃旧行动"), now)
		return
	actor.failures = 0
	_executor.begin(actor, result.value, observed.value, now)


## 完成一次行动，保存有限结果供下一次决策修正计划。
## [param actor] 行动角色。[param result] 实际结果。[param now] 单调毫秒。
func _finish(actor: AiPlayerActor, result: DomainResult, now: int) -> void:
	_record(actor, result, now)
	var details := {}
	if result.is_ok and result.value is Dictionary:
		for key: String in ["commerce", "manufacturing", "daily_activities"]:
			if result.value.has(key): details[key] = _bounded(result.value[key])
	_feedback[actor.key] = {"ok": result.is_ok, "code": String(result.error_code), "details": details}
	actor.action = null
	actor.next_decision = now + int(_settings.decision_interval_seconds * 1000)


## 将实际行动结果写入独立低优先级记忆，不向真人HUD广播AI错误。
## [param actor] 行动角色。[param result] 实际结果。[param now] 时间。
func _record(actor: AiPlayerActor, result: DomainResult, now: int) -> void:
	actor.remember(result, now)
	_memory.save(actor)
	if actor.paused: push_warning("AI角色%s已暂停：%s" % [actor.key, result.error_code])


## 对查询返回值逐层裁剪，禁止无限商品、描述与嵌套历史进入模型上下文。
## [param value] 自身查询结果。[param depth] 当前深度。
## 返回有限JSON值。
func _bounded(value: Variant, depth := 0) -> Variant:
	if depth >= 6: return null
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			if result.size() >= 24: break
			if String(key) in ["presentation", "source_audit"]: continue
			result[String(key).left(80)] = _bounded(value[key], depth + 1)
		return result
	if value is Array:
		var result := []
		for item: Variant in value.slice(0, 32): result.append(_bounded(item, depth + 1))
		return result
	return value.left(256) if value is String else value


## 取消网络、保存记忆并释放自身会话；可重复调用，不关闭真人连接。
func stop() -> void:
	if not running: return
	running = false
	_provider.cancel()
	_pending_actor = null
	_pending_view = null
	for actor: AiPlayerActor in actors:
		actor.pending_request = 0
		actor.action = null
		_memory.save(actor)
		var closed := _world.close_actor(actor)
		if not closed.is_ok: push_warning("AI退出保存失败：" + String(closed.error_code))
	actors.clear()
	_feedback.clear()
	var saved := _memory.close()
	if not saved.is_ok: push_warning("AI记忆保存失败：" + String(saved.error_code))


## 场景退出只回收本模块资源；服务器照常完成自己的保存。
func _exit_tree() -> void:
	stop()
