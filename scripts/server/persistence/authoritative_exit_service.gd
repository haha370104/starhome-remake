class_name AuthoritativeExitService
extends RefCounted

const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")

const RECEIPT_LIMIT := 128
var _autosave: AuthoritativeAutosaveService
var _capture: Callable
var _release: Callable
var _receipts: Dictionary[int, Dictionary] = {}


## 组合正常退出所需的唯一存档端口与世界收尾，不持有第二份玩家状态。
## [param autosave] 当前权威状态仓储。[param capture] 最新世界状态采集。
## [param release] 保存成功后结束角色世界运行和会话的无失败回调。
func _init(autosave: AuthoritativeAutosaveService, capture: Callable, release: Callable) -> void:
	_autosave = autosave
	_capture = capture
	_release = release


## 为正常退出采集并保存完整玩家状态，失败不释放实体或暂停正式订单。
## [param peer_id] 由传输提供的真实连接身份。[param session] 该连接当前会话，重试回执时可为空。
## [param command] 只接受唯一退出请求身份，不信任客户端存档内容。
## 返回已持久化且完成会话收尾的回执，重复请求复用同一回执。
func execute(peer_id: int, session: ServerSession, command: Dictionary) -> DomainResult:
	var identity: Variant = command.get("request_id")
	if not valid_request_id(identity): return DomainResult.failure(&"exit.invalid_request", "退出请求编号无效")
	if _receipts.has(peer_id) and session == null:
		var cached_receipt := _receipts[peer_id]
		if cached_receipt.request_id == identity: return DomainResult.ok({"exit_receipt": cached_receipt.duplicate(true)})
		return DomainResult.failure(&"exit.session_closed", "此会话已保存退出")
	if session == null or session.peer_id != peer_id:
		return DomainResult.failure(&"exit.session_missing", "当前没有可保存的角色会话")
	if _autosave == null or not _capture.is_valid() or not _release.is_valid():
		return DomainResult.failure(&"exit.unavailable", "存档服务尚未就绪")
	var current := _autosave.player_for(session.entity_id)
	if current == null: return DomainResult.failure(&"exit.state_missing", "当前角色状态不可用")
	var phase_started_at := PerformanceTelemetryScript.begin(&"server_exit_capture")
	var captured: DomainResult = _capture.call(current)
	PerformanceTelemetryScript.end(&"server_exit_capture", phase_started_at)
	if not captured.is_ok: return captured
	var prepared := PlayerTransaction.prepare(captured.value, ["production"], null)
	if not prepared.is_ok: return prepared
	var candidate: Player = prepared.value
	candidate.production.pause("退出游戏后生产已暂停")
	phase_started_at = PerformanceTelemetryScript.begin(&"server_exit_durable_commit")
	var committed := _autosave.commit_player(session.entity_id, candidate, true)
	PerformanceTelemetryScript.end(&"server_exit_durable_commit", phase_started_at)
	if not committed.is_ok: return committed
	var saved_revision := _autosave.saved_revision_for(session.entity_id)
	_release.call(session, committed.value)
	var receipt := {"request_id": String(identity), "saved_revision": saved_revision}
	_receipts[peer_id] = receipt
	if _receipts.size() > RECEIPT_LIMIT: _receipts.erase(_receipts.keys()[0])
	return DomainResult.ok({"exit_receipt": receipt.duplicate(true)})


## 新会话开始时移除该连接曾有的退出回执，防止连接编号复用混淆角色。
## [param peer_id] 已成功建立新会话的连接编号。
func forget(peer_id: int) -> void:
	_receipts.erase(peer_id)


## 限制回执关联身份为32位小写十六进制，拒绝任意长度与复杂载荷。
## [param value] 退出意图中的请求编号。
## 返回是否为受控身份。
static func valid_request_id(value: Variant) -> bool:
	if not value is String or value.length() != 32: return false
	for index in value.length():
		if not "0123456789abcdef".contains(value[index]): return false
	return true
