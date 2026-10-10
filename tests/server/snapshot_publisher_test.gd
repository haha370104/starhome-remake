extends SceneTree

const SnapshotPublisherScript := preload("res://scripts/server/snapshot_publisher.gd")
const ServerSessionScript := preload("res://scripts/server/server_session.gd")

var checks := 0
var failures: Array[String] = []
var event_order: Array[String] = []
var session: ServerSession
var second_session: ServerSession
var sent_world_snapshot: Dictionary = {}
var sent_local_snapshot: Dictionary = {}
var world_snapshot: Dictionary = {}
var local_snapshot: Dictionary = {}
var return_empty_local := false


func _initialize() -> void:
	_run()


func _run() -> void:
	var publisher: SnapshotPublisher = SnapshotPublisherScript.new()
	_check(not publisher.publish(1, 0.5).is_ok, "unconfigured publisher rejects publish")
	_check(not publisher.configure(
		Callable(), Callable(), Callable(), Callable(), Callable(), Callable(),
	).is_ok, "publisher rejects missing ports")

	session = ServerSessionScript.new()
	session.peer_id = 42
	session.map_instance_id = "alpha"
	second_session = ServerSessionScript.new()
	second_session.peer_id = 43
	second_session.map_instance_id = "alpha"
	publisher.peer_world_snapshot_generated.connect(_on_peer_world_snapshot_generated)
	publisher.peer_local_snapshot_generated.connect(_on_peer_local_snapshot_generated)
	_check(publisher.configure(
		Callable(self, "_map_instances"),
		Callable(self, "_active_sessions"),
		Callable(self, "_build_shared_snapshot"),
		Callable(self, "_build_local_snapshot"),
		Callable(self, "_send_world_snapshot"),
		Callable(self, "_send_local_snapshot"),
	).is_ok, "publisher accepts complete ports")

	var result := publisher.publish(7, 1.75)
	_check(result.is_ok, "publisher completes a normal publish")
	_check(event_order == [
		"shared_build", "peer_build", "peer_world_signal", "peer_local_signal", "send_world", "send_local",
		"peer_build", "peer_world_signal", "peer_local_signal", "send_world", "send_local",
	], "publisher preserves shared-before-peer-send order")
	_check(world_snapshot.get("server_tick") == 7, "shared snapshot receives server tick")
	_check(world_snapshot.get("server_time_seconds") == 1.75,
		"shared snapshot receives server time")
	_check(world_snapshot.is_read_only() and local_snapshot.is_read_only(), "both peer signals receive frozen snapshots")
	_check(sent_world_snapshot.is_read_only() and sent_local_snapshot.is_read_only(), "both senders receive frozen snapshots")
	_check(local_snapshot.get("peer_id") == 43, "each player receives its own local snapshot")
	_check(sent_local_snapshot.get("peer_id") == 43, "local sender receives the second session peer")

	event_order.clear()
	world_snapshot = {}
	local_snapshot = {}
	sent_world_snapshot = {}
	sent_local_snapshot = {}
	return_empty_local = true
	result = publisher.publish(8, 2.0)
	_check(result.is_ok, "publisher completes when peer snapshot is empty")
	_check(event_order == ["shared_build", "peer_build", "peer_build"],
		"empty local snapshot skips signal and transport send")

	for failure: String in failures:
		push_error(failure)
	print("SNAPSHOT_PUBLISHER_OK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _map_instances() -> Array:
	return [{"map_id": "alpha"}]


func _active_sessions() -> Array[ServerSession]:
	return [session, second_session]


func _build_shared_snapshot(_instance: Variant, server_tick: int, server_time_seconds: float) -> Dictionary:
	event_order.append("shared_build")
	return {
		"map_instance_id": "alpha",
		"server_tick": server_tick,
		"server_time_seconds": server_time_seconds,
	}


func _build_local_snapshot(peer_id: int) -> Dictionary:
	event_order.append("peer_build")
	if return_empty_local:
		return {}
	return {"peer_id": peer_id, "server_tick": 7}


func _send_world_snapshot(_peer_id: int, snapshot: Dictionary) -> void:
	event_order.append("send_world")
	sent_world_snapshot = snapshot


func _send_local_snapshot(_peer_id: int, snapshot: Dictionary) -> void:
	event_order.append("send_local")
	sent_local_snapshot = snapshot


func _on_peer_world_snapshot_generated(_peer_id: int, snapshot: Dictionary) -> void:
	event_order.append("peer_world_signal")
	world_snapshot = snapshot


func _on_peer_local_snapshot_generated(_peer_id: int, snapshot: Dictionary) -> void:
	event_order.append("peer_local_signal")
	local_snapshot = snapshot


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
