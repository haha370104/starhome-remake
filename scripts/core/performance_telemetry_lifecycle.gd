extends Node

var _elapsed := 0.0
var _last_render := 0
var _last_physics := 0


## 显式环境开关控制遥测；普通玩家不注册逐帧计时或额外文件线程。
func _ready() -> void:
	var enabled := OS.get_environment("STARHOME_PERFORMANCE").strip_edges().to_lower() in ["1", "true", "on"]
	set_process(enabled)
	set_physics_process(enabled)
	if not enabled: return
	var error := PerformanceTelemetry.configure(true, OS.get_environment("STARHOME_PERFORMANCE_OUTPUT"), {
		"engine": Engine.get_version_info().string, "os": OS.get_name(), "process_id": OS.get_process_id(),
		"scenario": OS.get_environment("STARHOME_PERFORMANCE_SCENARIO"),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
		"started_at": Time.get_datetime_string_from_system(true)})
	if error != OK:
		push_warning("无法启动性能统计：" + error_string(error))
		set_process(false)
		set_physics_process(false)
		return
	RenderingServer.frame_post_draw.connect(_rendered)


## 记录实际物理帧间隔，保留调度抖动而非固定delta。
## [param _delta] 引擎固定步长。
func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_physics > 0: PerformanceTelemetry.record_duration(&"physics_frame_interval", now - _last_physics)
	_last_physics = now


## 每30秒排队最新报告，普通游戏帧不执行文件刷新。
## [param delta] 渲染帧间隔。
func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 30.0:
		_elapsed = 0.0
		PerformanceTelemetry.submit_report()


## 从实际绘制完成时刻计算渲染帧间隔。
func _rendered() -> void:
	var now := Time.get_ticks_usec()
	if _last_render > 0: PerformanceTelemetry.record_duration(&"render_frame_interval", now - _last_render)
	_last_render = now


## 退出时等待报告完成；进程被强杀不保证最后一份统计落盘。
func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_rendered): RenderingServer.frame_post_draw.disconnect(_rendered)
	var result := PerformanceTelemetry.close()
	if not result.is_ok: push_warning(result.error_message)
