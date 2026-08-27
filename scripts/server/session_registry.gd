class_name SessionRegistry
extends RefCounted

const SessionScript := preload("res://scripts/server/server_session.gd")

var reconnect_grace_msec := 30000
var _next_session_number := 1
var _sessions_by_peer: Dictionary = {}
var _sessions_by_token: Dictionary = {}
var _sessions_by_entity: Dictionary = {}


## Configures the instance from validated runtime inputs.
## [param reconnect_grace_seconds] Elapsed time in seconds for this update.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func configure(reconnect_grace_seconds: float) -> void:
	reconnect_grace_msec = maxi(0, roundi(reconnect_grace_seconds * 1000.0))


## Builds the requested runtime object from configuration data.
## [param peer_id] Stable identifier of the target value.
## [param entity_id] Stable identifier of the target value.
## [param now_msec] Input value consumed by the operation.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
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


## Updates the managed state with the supplied value.
## [param peer_id] Stable identifier of the target value.
## [param now_msec] Input value consumed by the operation.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func mark_disconnected(peer_id: int, now_msec: int) -> Dictionary:
	var session: ServerSession = _sessions_by_peer.get(peer_id)
	if session == null:
		return _failure(&"unknown_peer", "peer has no active session")
	_sessions_by_peer.erase(peer_id)
	session.peer_id = 0
	session.disconnected_at_msec = now_msec
	session.expires_at_msec = now_msec + reconnect_grace_msec
	return _success(session)


## Performs the `reconnect` operation.
## [param peer_id] Stable identifier of the target value.
## [param reconnect_token] Input value consumed by the operation.
## [param now_msec] Input value consumed by the operation.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
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


## Performs the `cleanup_expired` operation.
## [param now_msec] Input value consumed by the operation.
## Returns the resulting string collection.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
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


## Retrieves the requested value from the managed state.
## [param peer_id] Stable identifier of the target value.
## Returns the result produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func session_for_peer(peer_id: int) -> ServerSession:
	return _sessions_by_peer.get(peer_id)


## Retrieves the requested value from the managed state.
## [param entity_id] Stable identifier of the target value.
## Returns the result produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func session_for_entity(entity_id: String) -> ServerSession:
	return _sessions_by_entity.get(entity_id)


## Performs the `active_sessions` operation.
## Returns the resulting collection.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func active_sessions() -> Array[ServerSession]:
	var result: Array[ServerSession] = []
	for session in _sessions_by_peer.values():
		result.append(session)
	return result


## Performs the `all_sessions` operation.
## Returns the resulting collection.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func all_sessions() -> Array[ServerSession]:
	var result: Array[ServerSession] = []
	for session in _sessions_by_token.values():
		result.append(session)
	return result


## Mutates the managed collection for the requested value.
## [param session] Input value consumed by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _remove_session(session: ServerSession) -> void:
	if session.peer_id > 0:
		_sessions_by_peer.erase(session.peer_id)
	_sessions_by_token.erase(session.reconnect_token)
	_sessions_by_entity.erase(session.entity_id)


## Builds the requested runtime object from configuration data.
## [param peer_id] Stable identifier of the target value.
## [param entity_id] Stable identifier of the target value.
## [param now_msec] Input value consumed by the operation.
## Returns the resolved string value.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _new_token(peer_id: int, entity_id: String, now_msec: int) -> String:
	var random_bytes := Crypto.new().generate_random_bytes(24)
	return "%s-%s" % [random_bytes.hex_encode(), str(hash([peer_id, entity_id, now_msec]))]


## Performs the `success` operation.
## [param value] New value requested by the caller.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _success(value: Variant) -> Dictionary:
	return {"ok": true, "code": &"ok", "value": value}


## Performs the `failure` operation.
## [param code] Stable identifier of the target value.
## [param message] Serialized input received at the subsystem boundary.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
