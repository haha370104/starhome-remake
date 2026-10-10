class_name AuthoritativeFoodRuntime
extends RefCounted

var _clock := -1
var _autosave: AuthoritativeAutosaveService
var _capture: Callable
var _apply: Callable
var _publish: Callable


## 组合食品时钟需要的仓储和运行时端口，不拥有第二份玩家状态。
## [param autosave] 唯一内存存档所有者。
## [param capture] 捕获战斗当前资源。
## [param apply] 将提交结果同步到战斗。
## [param publish] 发布在线玩家投影。
func _init(autosave: AuthoritativeAutosaveService,
		capture: Callable, apply: Callable, publish: Callable) -> void:
	_autosave = autosave
	_capture = capture
	_apply = apply
	_publish = publish


## 每秒推进食品效果，断线宽限期仍回收增益，但不发放离线回血。
## [param sessions] 当前仍由服务器拥有的会话。
## [param now] 权威 Unix 秒数；同一时刻多次调用不重复结算。
func advance(sessions: Array, now: int) -> void:
	if now == _clock:
		return
	_clock = now
	for session: ServerSession in sessions:
		var state := _autosave.player_for(session.entity_id)
		if state == null or state.food_status.active.is_empty():
			continue
		var expired := state.food_status.active.any(func(effect: FoodEffect) -> bool: return effect.kind >= 13 and effect.kind <= 17 and effect.expires_at <= now)
		if expired:
			var captured: DomainResult = _capture.call(state)
			if not captured.is_ok: continue
		var previous_health := state.health
		var previous_count := state.food_status.active.size()
		if not session.is_online():
			for effect: FoodEffect in state.food_status.active: effect.last_tick = now
		state.advance_food_status(now)
		if previous_health == state.health and previous_count == state.food_status.active.size(): continue
		var stored := _autosave.update_runtime_state(
			session.entity_id, state, ["character", "food"] as Array[String]
		)
		if not stored.is_ok:
			continue
		if expired: _apply.call(session.entity_id, stored.value)
		if session.has_active_peer():
			_publish.call(session.peer_id, stored.value, expired, previous_count != state.food_status.active.size())
