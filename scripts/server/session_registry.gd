class_name SessionRegistry
extends RefCounted

const SessionScript := preload("res://scripts/server/server_session.gd")

var reconnect_grace_msec := 30000
var _next_session_number := 1
var _sessions_by_peer: Dictionary = {}
var _sessions_by_token: Dictionary = {}
var _sessions_by_entity: Dictionary = {}


## 配置并初始化 `configure` 对应的模块状态。
## [param reconnect_grace_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func configure(reconnect_grace_seconds: float) -> void:
	reconnect_grace_msec = maxi(0, roundi(reconnect_grace_seconds * 1000.0))


## 执行 `create` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param now_msec] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
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


## 执行 `mark_disconnected` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param now_msec] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func mark_disconnected(peer_id: int, now_msec: int) -> Dictionary:
	var session: ServerSession = _sessions_by_peer.get(peer_id)
	if session == null:
		return _failure(&"unknown_peer", "peer has no active session")
	_sessions_by_peer.erase(peer_id)
	session.peer_id = 0
	session.disconnected_at_msec = now_msec
	session.expires_at_msec = now_msec + reconnect_grace_msec
	return _success(session)


## 正常退出保存成功后立即结束会话，与意外断线的重连宽限区分。
## [param peer_id] 已完成保存的真实连接身份。
## 返回已清理的会话或不存在错误；不自行读写玩家存档。
func close(peer_id: int) -> Dictionary:
	var session := session_for_peer(peer_id)
	if session == null: return _failure(&"unknown_peer", "peer has no active session")
	_remove_session(session)
	return _success(session)


## 执行 `reconnect` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param reconnect_token] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param now_msec] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func reconnect(peer_id: int, reconnect_token: String, now_msec: int) -> Dictionary:
	if peer_id <= 0:
		return _failure(&"invalid_peer", "peer_id must be positive")
	if _sessions_by_peer.has(peer_id):
		return _failure(&"peer_already_connected", "peer already owns a session")
	var session: ServerSession = _sessions_by_token.get(reconnect_token)
	if session == null:
		return _failure(&"invalid_reconnect_token", "reconnect token is unknown")
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


## 移除并清理 `cleanup_expired` 对应的模块状态。
## [param now_msec] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
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


## 执行 `session_for_peer` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func session_for_peer(peer_id: int) -> ServerSession:
	return _sessions_by_peer.get(peer_id)


## 执行 `session_for_entity` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func session_for_entity(entity_id: String) -> ServerSession:
	return _sessions_by_entity.get(entity_id)


## 执行 `active_sessions` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func active_sessions() -> Array[ServerSession]:
	var result: Array[ServerSession] = []
	for session in _sessions_by_peer.values():
		result.append(session)
	return result


## 执行 `all_sessions` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func all_sessions() -> Array[ServerSession]:
	var result: Array[ServerSession] = []
	for session in _sessions_by_token.values():
		result.append(session)
	return result


## 移除并清理 `remove_session` 对应的模块状态。
## [param session] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _remove_session(session: ServerSession) -> void:
	if session.peer_id > 0:
		_sessions_by_peer.erase(session.peer_id)
	_sessions_by_token.erase(session.reconnect_token)
	_sessions_by_entity.erase(session.entity_id)


## 执行 `new_token` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param now_msec] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _new_token(peer_id: int, entity_id: String, now_msec: int) -> String:
	var random_bytes := Crypto.new().generate_random_bytes(24)
	return "%s-%s" % [random_bytes.hex_encode(), str(hash([peer_id, entity_id, now_msec]))]


## 执行 `success` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _success(value: Variant) -> Dictionary:
	return {"ok": true, "code": &"ok", "value": value}


## 执行 `failure` 对应的模块操作。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
