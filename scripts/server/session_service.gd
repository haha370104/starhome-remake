class_name SessionService
extends RefCounted

const SessionScript := preload("res://scripts/server/server_session.gd")

var reconnect_grace_msec := 30000
var _next_session_number := 1
var _sessions_by_peer: Dictionary = {}
var _sessions_by_token: Dictionary = {}
var _sessions_by_entity: Dictionary = {}


## 配置并初始化 `configure` 对应的模块状态。
## [param reconnect_grace_seconds] 调用方传入的重连宽限秒数。
## 设计：会话生命周期策略只由服务端配置，客户端不能覆盖。
func configure(reconnect_grace_seconds: float) -> void:
	reconnect_grace_msec = maxi(0, roundi(reconnect_grace_seconds * 1000.0))


## 创建并登记一个新的网络控制会话。
## [param peer_id] 真实传输连接标识。
## [param entity_id] 已由服务器分配的角色标识。
## [param now_msec] 服务端当前时间。
## 返回创建结果及会话对象。
func create(peer_id: int, entity_id: String, now_msec: int) -> Dictionary:
	if peer_id <= 0:
		return _failure(&"invalid_peer", "peer_id must be positive")
	if entity_id.is_empty():
		return _failure(&"invalid_entity", "entity_id cannot be empty")
	if _sessions_by_peer.has(peer_id):
		return _failure(&"peer_already_connected", "peer already owns a session")
	if _sessions_by_entity.has(entity_id):
		return _failure(&"entity_already_owned", "entity already belongs to a session")
	var session: ServerSession = SessionScript.new()
	session.session_id = "session_%d" % _next_session_number
	_next_session_number += 1
	session.peer_id = peer_id
	session.entity_id = entity_id
	session.reconnect_token = _new_token(peer_id, entity_id, now_msec)
	_sessions_by_peer[peer_id] = session
	_sessions_by_token[session.reconnect_token] = session
	_sessions_by_entity[entity_id] = session
	return _success(session)


## 创建不绑定网络连接的独立 LLM 玩家会话。
## [param entity_id] 已由服务器校验的 LLM 角色标识。
## [param now_msec] 服务端当前时间。
## 返回创建结果及会话对象。
func create_llm(entity_id: String, now_msec: int) -> Dictionary:
	if entity_id.is_empty():
		return _failure(&"invalid_entity", "entity_id cannot be empty")
	if _sessions_by_entity.has(entity_id):
		return _failure(&"entity_already_owned", "entity already belongs to a session")
	var session: ServerSession = SessionScript.new()
	session.session_id = "session_%d" % _next_session_number
	_next_session_number += 1
	session.entity_id = entity_id
	session.is_llm = true
	session.reconnect_token = _new_token(0, entity_id, now_msec)
	_sessions_by_token[session.reconnect_token] = session
	_sessions_by_entity[entity_id] = session
	return _success(session)


## 将网络连接转为断线宽限状态，不释放角色身份。
## [param peer_id] 即将断开的真实连接标识。
## [param now_msec] 服务端当前时间。
## 返回更新后的会话。
func mark_disconnected(peer_id: int, now_msec: int) -> Dictionary:
	var session: ServerSession = _sessions_by_peer.get(peer_id)
	if session == null:
		return _failure(&"unknown_peer", "peer has no active session")
	_sessions_by_peer.erase(peer_id)
	session.peer_id = 0
	session.disconnected_at_msec = now_msec
	session.expires_at_msec = now_msec + reconnect_grace_msec
	return _success(session)


## 正常退出成功后立即结束会话。
## [param peer_id] 已完成持久化的真实连接标识。
## 返回被移除的会话。
func close(peer_id: int) -> Dictionary:
	var session := session_for_peer(peer_id)
	if session == null:
		return _failure(&"unknown_peer", "peer has no active session")
	_remove_session(session)
	return _success(session)


## 按角色标识结束不绑定网络的独立会话。
## [param entity_id] 要下线的 LLM 角色标识。
## 返回被移除的会话。
func close_entity(entity_id: String) -> Dictionary:
	var session := session_for_entity(entity_id)
	if session == null:
		return _failure(&"unknown_entity", "entity has no active session")
	_remove_session(session)
	return _success(session)


## 使用重连令牌恢复原角色的连接控制权。
## [param peer_id] 新的真实传输连接标识。
## [param reconnect_token] 原会话令牌。
## [param now_msec] 服务端当前时间。
## 返回恢复后的会话。
func reconnect(peer_id: int, reconnect_token: String, now_msec: int) -> Dictionary:
	if peer_id <= 0:
		return _failure(&"invalid_peer", "peer_id must be positive")
	if _sessions_by_peer.has(peer_id):
		return _failure(&"peer_already_connected", "peer already owns a session")
	var session: ServerSession = _sessions_by_token.get(reconnect_token)
	if session == null:
		return _failure(&"invalid_reconnect_token", "reconnect token is unknown")
	if session.is_llm:
		return _failure(&"llm_session_not_reconnectable", "LLM sessions cannot be reclaimed by a network peer")
	if session.has_active_peer():
		return _failure(&"session_already_connected", "session is controlled by another peer")
	if session.expires_at_msec >= 0 and now_msec > session.expires_at_msec:
		_remove_session(session)
		return _failure(&"reconnect_expired", "reconnect grace period elapsed")
	session.peer_id = peer_id
	session.disconnected_at_msec = -1
	session.expires_at_msec = -1
	_sessions_by_peer[peer_id] = session
	return _success(session)


## 删除超过断线宽限的会话并返回其角色标识。
## [param now_msec] 服务端当前时间。
## 返回已过期的角色标识列表。
func cleanup_expired(now_msec: int) -> PackedStringArray:
	var removed_entities := PackedStringArray()
	for token in _sessions_by_token.keys():
		var session: ServerSession = _sessions_by_token[token]
		if (
			not session.has_active_peer()
			and session.expires_at_msec >= 0
			and now_msec > session.expires_at_msec
		):
			removed_entities.append(session.entity_id)
			_remove_session(session)
	return removed_entities


## 按传输连接查询会话。
## [param peer_id] 真实连接标识。
## 返回活动会话或 null。
func session_for_peer(peer_id: int) -> ServerSession:
	return _sessions_by_peer.get(peer_id)


## 按角色标识查询会话。
## [param entity_id] 权威角色标识。
## 返回会话或 null。
func session_for_entity(entity_id: String) -> ServerSession:
	return _sessions_by_entity.get(entity_id)


## 在重连改变会话状态前按令牌查询会话。
## [param reconnect_token] 原会话令牌。
## 返回会话或 null。
func session_for_reconnect_token(reconnect_token: String) -> ServerSession:
	if reconnect_token.is_empty():
		return null
	return _sessions_by_token.get(reconnect_token)


## 返回当前仍由网络连接控制的会话。
func active_sessions() -> Array[ServerSession]:
	var result: Array[ServerSession] = []
	for session in _sessions_by_peer.values():
		result.append(session)
	return result


## 返回当前仍由网络或独立 LLM 控制的在线会话。
func online_sessions() -> Array[ServerSession]:
	var result: Array[ServerSession] = []
	for session: ServerSession in _sessions_by_token.values():
		if session.is_online():
			result.append(session)
	return result


## 返回包括断线宽限期在内的全部会话。
func all_sessions() -> Array[ServerSession]:
	var result: Array[ServerSession] = []
	for session in _sessions_by_token.values():
		result.append(session)
	return result


func _remove_session(session: ServerSession) -> void:
	if session.peer_id > 0:
		_sessions_by_peer.erase(session.peer_id)
	_sessions_by_token.erase(session.reconnect_token)
	_sessions_by_entity.erase(session.entity_id)


func _new_token(peer_id: int, entity_id: String, now_msec: int) -> String:
	var random_bytes := Crypto.new().generate_random_bytes(24)
	return "%s-%s" % [random_bytes.hex_encode(), str(hash([peer_id, entity_id, now_msec]))]


func _success(value: Variant) -> Dictionary:
	return {"ok": true, "code": &"ok", "value": value}


func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
