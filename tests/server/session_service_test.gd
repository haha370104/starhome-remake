extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var service := SessionService.new()
	service.configure(1.0)
	_check(not service.create(0, "actor.invalid", 0).ok, "invalid peer is rejected")
	var created := service.create(101, "actor.one", 100)
	_check(created.ok, "session is created")
	var session: ServerSession = created.value
	_check(service.session_for_peer(101) == session, "peer lookup returns created session")
	_check(service.session_for_entity("actor.one") == session, "entity lookup returns created session")
	_check(service.session_for_reconnect_token(session.reconnect_token) == session,
		"reconnect token lookup returns created session")
	_check(not service.create(101, "actor.two", 101).ok, "duplicate peer is rejected")
	_check(not service.create(102, "actor.one", 102).ok, "duplicate entity is rejected")
	_check(service.mark_disconnected(101, 200).ok, "disconnect moves session into grace period")
	_check(service.session_for_peer(101) == null and service.all_sessions().size() == 1,
		"disconnected session is not active but remains recoverable")
	_check(service.reconnect(102, session.reconnect_token, 500).ok, "reconnect restores session ownership")
	_check(service.session_for_peer(102) == session and session.expires_at_msec == -1,
		"reconnect clears grace expiry")
	_check(service.mark_disconnected(102, 1000).ok, "second disconnect enters grace period")
	var expired := service.cleanup_expired(2001)
	_check(expired == PackedStringArray(["actor.one"]), "expired cleanup returns removed entity")
	_check(service.session_for_entity("actor.one") == null \
		and service.session_for_reconnect_token(session.reconnect_token) == null,
		"expired cleanup removes entity and token indexes")
	var another := service.create(103, "actor.two", 3000)
	_check(another.ok, "second session is created")
	var another_session: ServerSession = another.value
	_check(service.close(103).ok, "normal close removes active session")
	_check(service.session_for_entity(another_session.entity_id) == null, "normal close removes entity index")
	for failure: String in failures:
		push_error(failure)
	print("SESSION_SERVICE_OK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
