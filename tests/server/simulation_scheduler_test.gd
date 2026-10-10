extends SceneTree

const SchedulerScript := preload("res://scripts/server/simulation_scheduler.gd")

var checks := 0
var failures: Array[String] = []
var events: Array[String] = []
var captured_refresh_flags: Array[bool] = []
var cleanup_times: Array[int] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var scheduler: SimulationScheduler = SchedulerScript.new()
	_check(not scheduler.advance(0.05).is_ok, "未配置调度器拒绝推进")
	_check(not scheduler.configure(20, 7, Callable(), Callable(), Callable(), Callable(), Callable()).is_ok,
		"非整除快照频率应拒绝配置")
	_check(not scheduler.configure(20, 10, Callable(), Callable(), Callable(), Callable(), Callable()).is_ok,
		"缺失端口应拒绝配置")
	var configured := scheduler.configure(
		20,
		10,
		Callable(self, "_advance_frame"),
		Callable(self, "_simulate_tick"),
		Callable(self, "_publish_snapshot"),
		Callable(self, "_capture_persistence"),
		Callable(self, "_cleanup"),
	)
	_check(configured.is_ok, "有效频率和完整端口应配置成功")
	var partial := scheduler.advance(0.025, 100)
	_check(partial.is_ok and partial.value == 0 and scheduler.current_tick == 0,
		"不足一个 tick 的时间应保留在 accumulator")
	_check(events == ["frame", "persistence", "cleanup"], "无 tick 帧仍执行帧边界副作用")
	events.clear()
	var advanced := scheduler.advance(0.475, 575)
	_check(advanced.is_ok and advanced.value == 10 and scheduler.current_tick == 10,
		"保留时间加后续帧应连续推进十个固定 tick")
	_check(events.count("tick") == 10, "每个固定 tick 只模拟一次")
	_check(events.count("snapshot") == 5, "20Hz 模拟与 10Hz 快照节奏一致")
	_check(events[0] == "frame" and events[1] == "tick" and events[3] == "snapshot",
		"调度顺序保持帧推进、模拟、结算、快照")
	_check(events[-2] == "persistence" and events[-1] == "cleanup",
		"持久化和会话清理在全部 tick 后执行")
	_check(captured_refresh_flags == [false, true], "任一 tick 的种群刷新标志汇总到帧级持久化")
	_check(cleanup_times == [100, 575], "显式清理时钟原样传给会话清理端口")

	for failure: String in failures:
		push_error(failure)
	print("SIMULATION_SCHEDULER_OK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _advance_frame(_elapsed_seconds: float) -> void:
	events.append("frame")


func _simulate_tick(tick: int, _fixed_delta: float) -> bool:
	events.append("tick")
	return tick == 3


func _publish_snapshot(tick: int) -> void:
	events.append("snapshot")
	_check(tick % 2 == 0, "快照只在配置的 tick 倍数发布")


func _capture_persistence(_elapsed_seconds: float, population_refresh_happened: bool) -> void:
	events.append("persistence")
	captured_refresh_flags.append(population_refresh_happened)


func _cleanup(now_msec: int) -> void:
	events.append("cleanup")
	cleanup_times.append(now_msec)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
