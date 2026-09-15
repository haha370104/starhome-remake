class_name AuthoritativeFoodRuntime
extends RefCounted

var _clock := -1
var _autosave: AuthoritativeAutosaveService
var _panels: AuthoritativePlayerPanelService
var _capture: Callable
var _apply: Callable
var _publish: Callable


## 组合食品时钟需要的仓储和运行时端口，不拥有第二份玩家状态。
## [param autosave] 唯一内存存档所有者。
## [param panels] 玩家领域映射和食品结算服务。
## [param capture] 捕获战斗当前资源。
## [param apply] 将提交结果同步到战斗。
## [param publish] 发布在线玩家投影。
func _init(autosave: AuthoritativeAutosaveService, panels: AuthoritativePlayerPanelService,
		capture: Callable, apply: Callable, publish: Callable) -> void:
	_autosave = autosave
	_panels = panels
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
		var state := _autosave.state_for(session.entity_id)
		if state == null or state.food_status.get("active", []).is_empty():
			continue
		var captured: DomainResult = _capture.call(state)
		if not captured.is_ok:
			continue
		state = captured.value
		if not session.has_active_peer():
			var paused := FoodStatus.new(state.food_status)
			paused.resume(now)
			state.food_status = paused.to_dictionary()
		var advanced := _panels.advance_food_status(state, now)
		if not advanced.is_ok:
			continue
		var stored := _autosave.update_runtime_state(session.entity_id, advanced.value)
		if not stored.is_ok:
			continue
		_apply.call(session.entity_id, stored.value)
		if session.has_active_peer():
			_publish.call(session.peer_id, stored.value)
