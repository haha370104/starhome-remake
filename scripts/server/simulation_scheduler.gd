class_name SimulationScheduler
extends RefCounted

const Result := preload("res://scripts/core/domain_result.gd")
const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")

var current_tick := 0
var _frame_index := 0
var _simulation_hz := 0
var _ticks_per_snapshot := 0
var _accumulator := 0.0
var _advance_frame: Callable
var _simulate_tick: Callable
var _publish_snapshot: Callable
var _capture_persistence: Callable
var _cleanup_sessions: Callable
var _diagnostic_entity_counts: Callable
var _configured := false


## 配置固定步进、快照节奏和帧边界副作用端口。
func configure(
	simulation_hz: int,
	snapshot_hz: int,
	advance_frame: Callable,
	simulate_tick: Callable,
	publish_snapshot: Callable,
	capture_persistence: Callable,
	cleanup_sessions: Callable,
	diagnostic_entity_counts: Callable = Callable(),
) -> DomainResult:
	if simulation_hz <= 0 or snapshot_hz <= 0 or snapshot_hz > simulation_hz \
			or simulation_hz % snapshot_hz != 0:
		return Result.failure(&"simulation_scheduler.invalid_rate", "tick rates must satisfy simulation_hz >= snapshot_hz > 0 and divide evenly")
	var ports := [advance_frame, simulate_tick, publish_snapshot, capture_persistence, cleanup_sessions]
	for port: Callable in ports:
		if not port.is_valid():
			return Result.failure(&"simulation_scheduler.invalid_port", "all simulation scheduler ports are required")
	_simulation_hz = simulation_hz
	_ticks_per_snapshot = floori(float(simulation_hz) / float(snapshot_hz))
	_advance_frame = advance_frame
	_simulate_tick = simulate_tick
	_publish_snapshot = publish_snapshot
	_capture_persistence = capture_persistence
	_cleanup_sessions = cleanup_sessions
	_diagnostic_entity_counts = diagnostic_entity_counts
	current_tick = 0
	_frame_index = 0
	_accumulator = 0.0
	_configured = true
	return Result.ok(self)


## 推进一个渲染/物理帧并执行其中所有固定模拟 tick，不丢弃积压。
func advance(elapsed_seconds: float, now_msec := -1) -> DomainResult:
	if not _configured:
		return Result.failure(&"simulation_scheduler.unconfigured", "simulation scheduler is not configured")
	if elapsed_seconds <= 0.0:
		return Result.ok(0)
	_frame_index += 1
	_advance_frame.call(elapsed_seconds)
	_accumulator += elapsed_seconds
	var fixed_delta := 1.0 / float(_simulation_hz)
	var pending_ticks := floori((_accumulator + 0.000001) / fixed_delta)
	if pending_ticks > 1:
		PerformanceTelemetryScript.increment(&"server_accumulator_backlog_ticks", pending_ticks - 1)
		PerformanceTelemetryScript.record_duration(
			&"server_accumulator_backlog", roundi(_accumulator * 1000000.0)
		)
	var population_refresh_happened := false
	var executed_ticks := 0
	var threshold_events: Array[Dictionary] = []
	while _accumulator + 0.000001 >= fixed_delta:
		_accumulator -= fixed_delta
		current_tick += 1
		var tick_started_at := PerformanceTelemetryScript.begin(&"server_tick")
		var snapshot_due := current_tick % _ticks_per_snapshot == 0
		PerformanceTelemetryScript.begin_tick_diagnostics(
			current_tick, _frame_index, snapshot_due, maxi(0, pending_ticks - executed_ticks - 1),
		)
		var tick_population_refresh := bool(
			_simulate_tick.call(current_tick, fixed_delta)
		)
		population_refresh_happened = tick_population_refresh or population_refresh_happened
		if snapshot_due:
			_publish_snapshot.call(current_tick)
		var tick_duration_usec := Time.get_ticks_usec() - tick_started_at if tick_started_at > 0 else 0
		PerformanceTelemetryScript.end(&"server_tick", tick_started_at)
		var threshold_event := PerformanceTelemetryScript.finish_tick_diagnostics(
			tick_duration_usec, tick_population_refresh,
		)
		if not threshold_event.is_empty():
			if _diagnostic_entity_counts.is_valid():
				var entity_counts: Dictionary = _diagnostic_entity_counts.call()
				threshold_event["player_count"] = int(entity_counts.get("player_count", 0))
				threshold_event["monster_count"] = int(entity_counts.get("monster_count", 0))
			threshold_events.append(threshold_event)
		executed_ticks += 1
	var persistence_capture_usec := 0
	var persistence_started_at := Time.get_ticks_usec() if not threshold_events.is_empty() else 0
	_capture_persistence.call(elapsed_seconds, population_refresh_happened)
	if persistence_started_at > 0:
		persistence_capture_usec = Time.get_ticks_usec() - persistence_started_at
		for threshold_event: Dictionary in threshold_events:
			PerformanceTelemetryScript.record_threshold_event(
				threshold_event, persistence_capture_usec, population_refresh_happened,
			)
	var cleanup_time := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	_cleanup_sessions.call(cleanup_time)
	return Result.ok(executed_ticks)
