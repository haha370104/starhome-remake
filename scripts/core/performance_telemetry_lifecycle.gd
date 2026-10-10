extends Node

const Telemetry := preload("res://scripts/core/performance_telemetry.gd")

var _last_physics_usec := 0
var _last_render_usec := 0
var _started_at_usec := 0
var _quit_after_usec := 0
var _client_startup_start_consumed := false


func _enter_tree() -> void:
	_started_at_usec = Time.get_ticks_usec()


func take_client_startup_started_at_usec() -> int:
	if _client_startup_start_consumed:
		return Time.get_ticks_usec()
	_client_startup_start_consumed = true
	return _started_at_usec


func _ready() -> void:
	var metadata := {
		"godot_version": Engine.get_version_info(),
		"os_name": OS.get_name(),
		"process_id": OS.get_process_id(),
		"renderer": ProjectSettings.get_setting(
			"rendering/renderer/rendering_method", "unknown"
		),
		"resolution": _resolution(),
		"scenario": OS.get_environment("STARHOME_PERFORMANCE_SCENARIO"),
		"map_id": OS.get_environment("STARHOME_PERFORMANCE_MAP_ID"),
		"monster_count": _environment_int("STARHOME_PERFORMANCE_MONSTER_COUNT"),
		"player_count": _environment_int("STARHOME_PERFORMANCE_PLAYER_COUNT"),
		"server_mode": OS.get_environment("STARHOME_PERFORMANCE_SERVER_MODE"),
		"warmup_seconds": _environment_float("STARHOME_PERFORMANCE_WARMUP_SECONDS"),
		"sample_seconds": _environment_float("STARHOME_PERFORMANCE_SAMPLE_SECONDS"),
		"started_at_unix_ms": roundi(Time.get_unix_time_from_system() * 1000.0),
	}
	Telemetry.configure(
		_environment_enabled(),
		OS.get_environment(Telemetry.OUTPUT_ENVIRONMENT),
		metadata,
	)
	_quit_after_usec = maxi(
		0,
		roundi(float(OS.get_environment("STARHOME_PERFORMANCE_TOTAL_SECONDS")) * 1000000.0),
	)
	if not Telemetry.is_enabled():
		return
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _physics_process(_delta: float) -> void:
	if not Telemetry.is_enabled():
		return
	var now_usec := Time.get_ticks_usec()
	if _last_physics_usec > 0:
		Telemetry.record_duration(&"physics_frame_interval", now_usec - _last_physics_usec)
	_last_physics_usec = now_usec


func _process(_delta: float) -> void:
	if not Telemetry.is_enabled() or _quit_after_usec <= 0 or _started_at_usec <= 0:
		return
	if Time.get_ticks_usec() - _started_at_usec >= _quit_after_usec:
		get_tree().quit()


func _on_frame_post_draw() -> void:
	if not Telemetry.is_enabled():
		return
	var now_usec := Time.get_ticks_usec()
	if _last_render_usec > 0:
		Telemetry.record_duration(&"render_frame_interval", now_usec - _last_render_usec)
	_last_render_usec = now_usec


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	Telemetry.write_report()


func _environment_enabled() -> bool:
	if not OS.has_environment(Telemetry.ENVIRONMENT_FLAG):
		return false
	var value := OS.get_environment(Telemetry.ENVIRONMENT_FLAG).strip_edges().to_lower()
	return value not in ["", "0", "false", "off", "no"]


func _environment_int(environment_variable_name: String) -> int:
	return int(OS.get_environment(environment_variable_name)) \
		if OS.has_environment(environment_variable_name) else 0


func _environment_float(environment_variable_name: String) -> float:
	return float(OS.get_environment(environment_variable_name)) \
		if OS.has_environment(environment_variable_name) else 0.0


func _resolution() -> Array[int]:
	var size := DisplayServer.window_get_size()
	return [size.x, size.y]
