class_name AuthoritativeProductionRuntime
extends RefCounted

signal failed(peer_id: int, code: StringName, message: String)

class Clock extends RefCounted:
	var order_id := ""
	var revision := 0
	var remaining := 0.0
	var check_delay := 0.0
	var retry_delay := 0.0
	var pending_pause := ""

var _clocks: Dictionary[String, Clock] = {}
var _errors: Dictionary[String, StringName] = {}
var _autosave: AuthoritativeAutosaveService
var _sessions: SessionRegistry
var _manufacturing: AuthoritativeManufacturingService
var _capture: Callable
var _publish: Callable


## 组合服务器时钟与现有仓储，运行层只持有短期倒计时，不拥有另一份背包或订单成果。
## [param autosave] 唯一玩家状态所有者。
## [param sessions] 当前会话注册表。
## [param manufacturing] 已初始化的生产事务服务。
## [param capture_state] 捕获最新地图、资源和剩余等待的端口。
## [param publish] 发布已提交的生产结果。
func _init(autosave: AuthoritativeAutosaveService, sessions: SessionRegistry, manufacturing: AuthoritativeManufacturingService,
		capture_state: Callable, publish: Callable) -> void:
	_autosave = autosave
	_sessions = sessions
	_manufacturing = manufacturing
	_capture = capture_state
	_publish = publish


## 只跟踪已提交的运行订单；暂停、取消和完成会立即移除倒计时。
## [param state] 当前已提交记录。
func track(state: PlayerStateRecord) -> void:
	var order := state.production.order
	if order == null or order.paused:
		_clocks.erase(state.character_id)
		_errors.erase(state.character_id)
		return
	var existing: Clock = _clocks.get(state.character_id)
	if existing != null and existing.order_id == order.id and existing.revision == state.production.revision: return
	var clock := Clock.new()
	clock.order_id = order.id
	clock.revision = state.production.revision
	clock.remaining = order.remaining_milliseconds
	_clocks[state.character_id] = clock


## 将当前倒计时写入待保存副本，版本或订单不匹配时不覆盖新状态。
## [param state] 自动保存或事务准备中的隔离记录。
func capture(state: PlayerStateRecord) -> void:
	var clock: Clock = _clocks.get(state.character_id)
	if clock != null:
		state.production.capture_remaining(clock.order_id, clock.revision, ceili(maxf(0, clock.remaining)))


## 只推进有订单的角色，每次调用每人最多结算一轮，长帧不会补跑全部积压次数。
## [param elapsed_seconds] 服务器模拟实际经过时间，不接收网络时间。
## 设计：普通帧只递减轻量时钟，最多每250毫秒检查玩家状态，避免每帧还原完整聚合。
func advance(elapsed_seconds: float) -> void:
	if not is_finite(elapsed_seconds) or elapsed_seconds <= 0: return
	var elapsed := elapsed_seconds * 1000.0
	for entity_id: String in _clocks.keys():
		var clock := _clocks[entity_id]
		clock.remaining = maxf(0, clock.remaining - elapsed)
		clock.check_delay -= elapsed
		clock.retry_delay = maxf(0, clock.retry_delay - elapsed)
		if clock.retry_delay > 0 or (clock.remaining > 0 and clock.check_delay > 0): continue
		clock.check_delay = 250.0
		var session := _sessions.session_for_entity(entity_id)
		var state := _autosave.state_for(entity_id)
		if session == null or state == null:
			_clocks.erase(entity_id)
			_errors.erase(entity_id)
			continue
		if state.production.order == null or state.production.order.paused or state.production.revision != clock.revision:
			track(state)
			continue
		var captured: DomainResult = _capture.call(state)
		if not captured.is_ok:
			_failed(session, captured)
			continue
		state = captured.value
		var order := state.production.order
		if not clock.pending_pause.is_empty() or not session.has_active_peer() or state.map_id != order.map_id or state.vehicle_health <= 0:
			var reason := "断线后生产已暂停" if not session.has_active_peer() else "离开设施地图或战车被击毁，生产已暂停"
			if not clock.pending_pause.is_empty(): reason = clock.pending_pause
			state.production.pause(reason)
			_commit(state, {"station_id": order.station_id, "action": "pause_production", "message": reason}, session)
			continue
		if clock.remaining > 0: continue
		var completed := _manufacturing.complete_production_cycle(state)
		if not completed.is_ok:
			_failed(session, completed)
			continue
		_commit(completed.value.candidate, completed.value.operation, session)


## 在断线等明确生命周期事件中立即暂停，避免快速重连赶在下一次时钟检查前继续生产。
## [param entity_id] 已确认的角色身份。
## [param reason] 生命周期暂停原因。
## 返回已提交状态或拒绝；失败由短期时钟退避重试。
func interrupt(entity_id: String, reason: String) -> DomainResult:
	var state := _autosave.state_for(entity_id)
	var session := _sessions.session_for_entity(entity_id)
	if state == null or session == null or state.production.order == null or state.production.order.paused:
		return DomainResult.ok(false)
	var clock: Clock = _clocks.get(entity_id)
	if clock != null: clock.pending_pause = reason
	var captured: DomainResult = _capture.call(state)
	if not captured.is_ok:
		_failed(session, captured)
		return captured
	state = captured.value
	state.production.pause(reason)
	return _commit(state, {"station_id": state.production.order.station_id, "action": "pause_production", "message": reason}, session)


## 通过同一个仓储提交产物、材料、经验与订单进度，确认成功后才启动下一轮并发布。
## [param candidate] 领域服务返回的完整候选。
## [param operation] 本轮或暂停结果。
## [param session] 当前人物会话。
## 返回真实存档提交结果。
func _commit(candidate: PlayerStateRecord, operation: Dictionary, session: ServerSession) -> DomainResult:
	var saved := _autosave.commit_player_state(session.entity_id, candidate)
	if not saved.is_ok:
		_failed(session, saved)
		return saved
	_errors.erase(session.entity_id)
	track(saved.value)
	if session.has_active_peer(): _publish.call(session.peer_id, saved.value, operation)
	return saved


## 对持续故障退避一秒并只提示新的错误，未提交成果不发送成功消息。
## [param session] 出错的权威会话。
## [param result] 捕获、领域或仓储错误。
func _failed(session: ServerSession, result: DomainResult) -> void:
	var clock: Clock = _clocks.get(session.entity_id)
	if clock != null: clock.retry_delay = 1000.0
	if _errors.get(session.entity_id) == result.error_code: return
	_errors[session.entity_id] = result.error_code
	if session.has_active_peer(): failed.emit(session.peer_id, result.error_code, "生产暂未入账：" + result.error_message)
