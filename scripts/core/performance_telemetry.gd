class_name PerformanceTelemetry
extends RefCounted

const SCHEMA_VERSION := 1
const ENVIRONMENT_FLAG := "STARHOME_PERFORMANCE"
const OUTPUT_ENVIRONMENT := "STARHOME_PERFORMANCE_OUTPUT"
const MAX_SAMPLES_PER_METRIC := 100000
const ALWAYS_SAMPLED_METRIC_PREFIXES := [
	"client_startup_",
	"client_exit_",
	"server_exit_",
	"autosave_durable_",
	"autosave_background_",
]
const SERVER_TICK_TARGET_USEC := 16700
const SERVER_TICK_SPIKE_USEC := 33400
const MAX_THRESHOLD_EVENTS := 2048
const TICK_PHASE_FIELDS := {
	"server_simulate_world": "simulate_world_usec",
	"server_map_entity_movement": "entity_movement_usec",
	"server_map_combat_advance": "combat_advance_usec",
	"server_combat_actor_effects": "combat_actor_effects_usec",
	"server_combat_monster_simulation": "combat_monster_simulation_usec",
	"server_monster_route_planning": "monster_route_planning_usec",
	"server_settle_domain_events": "settle_domain_events_usec",
	"server_snapshot_publish": "snapshot_publish_usec",
	"server_snapshot_build": "snapshot_build_usec",
	"server_snapshot_freeze": "snapshot_freeze_usec",
	"server_snapshot_transport_dispatch": "snapshot_transport_dispatch_usec",
}

static var _configured := false
static var _enabled := false
static var _output_path := ""
static var _metadata: Dictionary = {}
static var _samples: Dictionary = {}
static var _counters: Dictionary = {}
static var _gauges: Dictionary = {}
static var _threshold_events: Array[Dictionary] = []
static var _active_tick_diagnostic: Dictionary = {}
static var _started_at_usec := 0
static var _warmup_usec := 0
static var _sample_usec := 0
static var _mutex := Mutex.new()


static func configure(enabled: bool, output_path: String = "", metadata: Dictionary = {}) -> void:
	_mutex.lock()
	_configured = true
	_enabled = enabled
	_output_path = output_path
	_metadata = metadata.duplicate(true)
	_samples.clear()
	_counters.clear()
	_gauges.clear()
	_threshold_events.clear()
	_active_tick_diagnostic.clear()
	_started_at_usec = Time.get_ticks_usec()
	_warmup_usec = maxi(0, roundi(float(_metadata.get("warmup_seconds", 0.0)) * 1000000.0))
	_sample_usec = maxi(0, roundi(float(_metadata.get("sample_seconds", 0.0)) * 1000000.0))
	_mutex.unlock()


static func is_enabled() -> bool:
	_ensure_configured()
	_mutex.lock()
	var enabled := _enabled
	_mutex.unlock()
	return enabled


static func annotate(metadata: Dictionary) -> void:
	if not is_enabled() or metadata.is_empty():
		return
	_mutex.lock()
	_metadata.merge(metadata, true)
	_mutex.unlock()


static func begin(_metric: StringName) -> int:
	if not is_enabled():
		return 0
	return Time.get_ticks_usec()


static func end(metric: StringName, started_at_usec: int) -> void:
	if started_at_usec <= 0 or not is_enabled():
		return
	record_duration(metric, Time.get_ticks_usec() - started_at_usec)


static func begin_tick_diagnostics(
	tick_index: int,
	frame_index: int,
	snapshot_due: bool,
	backlog_ticks: int,
) -> void:
	_active_tick_diagnostic.clear()
	if not _enabled:
		return
	_mutex.lock()
	if _in_sample_window_unlocked():
		_active_tick_diagnostic = {
			"kind": "server_tick",
			"tick_index": tick_index,
			"frame_index": frame_index,
			"snapshot_due": snapshot_due,
			"backlog_ticks": backlog_ticks,
			"map_id": String(_metadata.get("actual_map_id", _metadata.get("map_id", ""))),
			"player_count": int(_metadata.get("actual_player_count", _metadata.get("player_count", 0))),
			"monster_count": int(_metadata.get("actual_monster_count", _metadata.get("monster_count", 0))),
			"phase_usec": {},
		}
	_mutex.unlock()


static func finish_tick_diagnostics(duration_usec: int, population_refresh: bool) -> Dictionary:
	var event := {}
	if not _enabled:
		_active_tick_diagnostic.clear()
		return event
	_mutex.lock()
	if not _active_tick_diagnostic.is_empty() and duration_usec > SERVER_TICK_TARGET_USEC \
			and _in_sample_window_unlocked():
		event = _active_tick_diagnostic.duplicate(true)
		event["duration_usec"] = duration_usec
		event["over_33_4ms"] = duration_usec > SERVER_TICK_SPIKE_USEC
		event["population_refresh"] = population_refresh
	_active_tick_diagnostic.clear()
	_mutex.unlock()
	return event


static func record_threshold_event(event: Dictionary, persistence_capture_usec: int, frame_population_refresh: bool) -> void:
	if event.is_empty() or not _enabled:
		return
	_mutex.lock()
	if not _in_sample_window_unlocked():
		_mutex.unlock()
		return
	var duration_usec := int(event.get("duration_usec", 0))
	_counters["server_tick_over_16_7ms"] = int(_counters.get("server_tick_over_16_7ms", 0)) + 1
	if duration_usec > SERVER_TICK_SPIKE_USEC:
		_counters["server_tick_over_33_4ms"] = int(_counters.get("server_tick_over_33_4ms", 0)) + 1
	event["frame_persistence_capture_usec"] = persistence_capture_usec
	event["frame_population_refresh"] = frame_population_refresh
	if _threshold_events.size() < MAX_THRESHOLD_EVENTS:
		_threshold_events.append(event)
	else:
		_counters["server_tick_threshold_events_dropped"] = int(
			_counters.get("server_tick_threshold_events_dropped", 0)
		) + 1
	_mutex.unlock()


static func record_duration(metric: StringName, duration_usec: int) -> void:
	if not is_enabled() or duration_usec < 0:
		return
	var metric_name := String(metric)
	_mutex.lock()
	if not _in_sample_window_unlocked():
		var keep_outside_sample := false
		for prefix: String in ALWAYS_SAMPLED_METRIC_PREFIXES:
			if metric_name.begins_with(prefix):
				keep_outside_sample = true
				break
		if not keep_outside_sample:
			_mutex.unlock()
			return
	if not _active_tick_diagnostic.is_empty() and TICK_PHASE_FIELDS.has(metric_name):
		var phase_field: String = TICK_PHASE_FIELDS[metric_name]
		var phases: Dictionary = _active_tick_diagnostic["phase_usec"]
		phases[phase_field] = int(phases.get(phase_field, 0)) + duration_usec
	var samples: Array = _samples.get(String(metric), [])
	if samples.size() < MAX_SAMPLES_PER_METRIC:
		samples.append(duration_usec)
	_samples[String(metric)] = samples
	_mutex.unlock()


static func increment(counter: StringName, amount := 1) -> void:
	if not is_enabled():
		return
	_mutex.lock()
	if not _in_sample_window_unlocked():
		_mutex.unlock()
		return
	_counters[String(counter)] = int(_counters.get(String(counter), 0)) + amount
	_mutex.unlock()


static func set_gauge(gauge: StringName, value: float) -> void:
	if not is_enabled():
		return
	_mutex.lock()
	_gauges[String(gauge)] = value
	_mutex.unlock()


static func write_report(output_path := "", extra_metadata: Dictionary = {}) -> void:
	if not is_enabled():
		return
	_mutex.lock()
	var target_path := output_path if not output_path.is_empty() else _output_path
	var metadata := _metadata.duplicate(true)
	var samples := _samples.duplicate(true)
	var counters := _counters.duplicate(true)
	var gauges := _gauges.duplicate(true)
	var threshold_events := _threshold_events.duplicate(true)
	_mutex.unlock()
	if target_path.is_empty():
		return
	if target_path.begins_with("res://") or target_path.begins_with("user://"):
		target_path = ProjectSettings.globalize_path(target_path)
	var parent_error := DirAccess.make_dir_recursive_absolute(target_path.get_base_dir())
	if parent_error != OK and parent_error != ERR_ALREADY_EXISTS:
		push_warning("无法创建性能遥测目录：%s" % target_path.get_base_dir())
		return
	var document := {
		"schema_version": SCHEMA_VERSION,
		"metadata": metadata.merged(extra_metadata),
		"metrics": _summaries(samples),
		"counters": counters,
		"gauges": gauges,
		"threshold_events": threshold_events,
		"generated_at_unix_ms": roundi(Time.get_unix_time_from_system() * 1000.0),
	}
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		push_warning("无法写入性能遥测：%s" % target_path)
		return
	file.store_string(JSON.stringify(document, "  "))
	file.close()


static func _ensure_configured() -> void:
	_mutex.lock()
	if _configured:
		_mutex.unlock()
		return
	_configured = true
	_enabled = _environment_enabled()
	_output_path = OS.get_environment(OUTPUT_ENVIRONMENT)
	_mutex.unlock()


static func _environment_enabled() -> bool:
	if not OS.has_environment(ENVIRONMENT_FLAG):
		return false
	var value := OS.get_environment(ENVIRONMENT_FLAG).strip_edges().to_lower()
	return value not in ["", "0", "false", "off", "no"]


static func _in_sample_window() -> bool:
	_mutex.lock()
	var result := _in_sample_window_unlocked()
	_mutex.unlock()
	return result


static func _in_sample_window_unlocked() -> bool:
	if _started_at_usec <= 0:
		return false
	var elapsed_usec := Time.get_ticks_usec() - _started_at_usec
	if elapsed_usec < _warmup_usec:
		return false
	return _sample_usec <= 0 or elapsed_usec < _warmup_usec + _sample_usec


static func _summaries(samples: Dictionary) -> Dictionary:
	var result := {}
	for metric: String in samples:
		var values: Array = samples[metric].duplicate()
		values.sort()
		if values.is_empty():
			continue
		var total := 0.0
		for value: int in values:
			total += value
		result[metric] = {
			"count": values.size(),
			"mean_usec": total / values.size(),
			"p50_usec": _percentile(values, 0.50),
			"p95_usec": _percentile(values, 0.95),
			"p99_usec": _percentile(values, 0.99),
			"max_usec": values.back(),
		}
	return result


static func _percentile(sorted_values: Array, percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := floori(float(sorted_values.size() - 1) * percentile)
	return float(sorted_values[clampi(index, 0, sorted_values.size() - 1)])
