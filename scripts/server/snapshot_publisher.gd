class_name SnapshotPublisher
extends RefCounted

const Result := preload("res://scripts/core/domain_result.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")

signal peer_world_snapshot_generated(peer_id: int, snapshot: Dictionary)
signal peer_local_snapshot_generated(peer_id: int, snapshot: Dictionary)

var _map_instances: Callable
var _active_sessions: Callable
var _world_snapshot_builder: Callable
var _local_snapshot_builder: Callable
var _world_snapshot_sender: Callable
var _local_snapshot_sender: Callable
var _configured := false


## 配置快照发布所需的读取、构建和发送端口。
## [param map_instances] 返回当前已注册地图实例。
## [param active_sessions] 返回当前仍在线的会话。
## [param shared_snapshot_builder] 构建一份地图共享快照。
## [param local_snapshot_builder] 构建一个角色私有快照。
## [param world_snapshot_sender] 发送已冻结的地图共享快照。
## [param local_snapshot_sender] 发送已冻结的角色私有快照。
func configure(
	map_instances: Callable,
	active_sessions: Callable,
	world_snapshot_builder: Callable,
	local_snapshot_builder: Callable,
	world_snapshot_sender: Callable,
	local_snapshot_sender: Callable,
) -> DomainResult:
	var ports := [
		map_instances,
		active_sessions,
		world_snapshot_builder,
		local_snapshot_builder,
		world_snapshot_sender,
		local_snapshot_sender,
	]
	for port: Callable in ports:
		if not port.is_valid():
			return Result.failure(&"snapshot_publisher.invalid_port", "all snapshot publisher ports are required")
	_map_instances = map_instances
	_active_sessions = active_sessions
	_world_snapshot_builder = world_snapshot_builder
	_local_snapshot_builder = local_snapshot_builder
	_world_snapshot_sender = world_snapshot_sender
	_local_snapshot_sender = local_snapshot_sender
	_configured = true
	return Result.ok(self)


## 依次发布共享地图快照和各在线角色私有快照。
## [param server_tick] 当前权威服务器 tick。
## [param server_time_seconds] 当前权威服务器时间。
## 返回构建或发布失败；失败不会伪造已发布信号。
func publish(server_tick: int, server_time_seconds: float) -> DomainResult:
	if not _configured:
		return Result.failure(&"snapshot_publisher.unconfigured", "snapshot publisher is not configured")
	var publish_started_at := PerformanceTelemetryScript.begin(&"server_snapshot_publish")
	var instances: Variant = _map_instances.call()
	if not instances is Array:
		PerformanceTelemetryScript.end(&"server_snapshot_publish", publish_started_at)
		return Result.failure(&"snapshot_publisher.invalid_instances", "map instance port must return an Array")
	var worlds_by_map: Dictionary = {}
	for registered_instance: Variant in instances:
		var shared_started_at := PerformanceTelemetryScript.begin(&"server_snapshot_build")
		var world_snapshot: Variant = _world_snapshot_builder.call(
			registered_instance, server_tick, server_time_seconds
		)
		PerformanceTelemetryScript.end(&"server_snapshot_build", shared_started_at)
		if not world_snapshot is Dictionary or not world_snapshot.has("map_instance_id"):
			PerformanceTelemetryScript.end(&"server_snapshot_publish", publish_started_at)
			return Result.failure(&"snapshot_publisher.invalid_snapshot", "world snapshot must include map_instance_id")
		var world: Dictionary = world_snapshot
		var freeze_started_at := PerformanceTelemetryScript.begin(&"server_snapshot_freeze")
		Protocol.freeze_snapshot(world)
		PerformanceTelemetryScript.end(&"server_snapshot_freeze", freeze_started_at)
		worlds_by_map[String(world["map_instance_id"])] = world
	var sessions: Variant = _active_sessions.call()
	if not sessions is Array:
		PerformanceTelemetryScript.end(&"server_snapshot_publish", publish_started_at)
		return Result.failure(&"snapshot_publisher.invalid_sessions", "session port must return an Array")
	for session: ServerSession in sessions:
		var world_value: Variant = worlds_by_map.get(session.map_instance_id)
		if not world_value is Dictionary:
			continue
		var peer_started_at := PerformanceTelemetryScript.begin(&"server_snapshot_build")
		var local_snapshot: Variant = _local_snapshot_builder.call(session.peer_id)
		PerformanceTelemetryScript.end(&"server_snapshot_build", peer_started_at)
		if not local_snapshot is Dictionary or local_snapshot.is_empty():
			continue
		var local: Dictionary = local_snapshot
		var freeze_started_at := PerformanceTelemetryScript.begin(&"server_snapshot_freeze")
		Protocol.freeze_snapshot(local)
		PerformanceTelemetryScript.end(&"server_snapshot_freeze", freeze_started_at)
		var world: Dictionary = world_value
		peer_world_snapshot_generated.emit(session.peer_id, world)
		peer_local_snapshot_generated.emit(session.peer_id, local)
		var send_started_at := PerformanceTelemetryScript.begin(&"server_snapshot_transport_dispatch")
		_world_snapshot_sender.call(session.peer_id, world)
		_local_snapshot_sender.call(session.peer_id, local)
		PerformanceTelemetryScript.end(&"server_snapshot_transport_dispatch", send_started_at)
	PerformanceTelemetryScript.end(&"server_snapshot_publish", publish_started_at)
	return Result.ok()
