extends SceneTree

const CombatTraceLogger := preload("res://scripts/core/combat_trace_logger.gd")

var failures: Array[String] = []
var assertions := 0
var trace_path := ""


## 运行 JSONL 战斗诊断的落盘、类型转换和关联字段回归测试。
func _initialize() -> void:
	trace_path = "res://.godot/combat_trace_test_%d.jsonl" % OS.get_process_id()
	CombatTraceLogger.configure(true, trace_path)
	CombatTraceLogger.record(&"client", &"visual_projectile_collision", {
		"input_sequence": 17,
		"visual_shot_id": "visual.test.17",
		"position": Vector2(12.5, 34.0),
		"event_type": &"energy_cannon_hit",
	})
	_expect(FileAccess.file_exists(trace_path), "诊断日志应写入显式测试路径")
	var line := FileAccess.get_file_as_string(trace_path).strip_edges()
	var parsed: Variant = JSON.parse_string(line)
	_expect(parsed is Dictionary, "每一行都应是独立 JSON 对象")
	if parsed is Dictionary:
		var entry: Dictionary = parsed
		var fields: Dictionary = entry.get("fields", {})
		_expect(entry.get("schema_version") == 1, "日志必须携带结构版本")
		_expect(entry.get("side") == "client", "日志必须保留客户端或服务端边界")
		_expect(entry.get("stage") == "visual_projectile_collision", "日志必须保留链路阶段")
		_expect(fields.get("position") == [12.5, 34.0], "Vector2 必须转换为 JSON 数组")
		_expect(fields.get("event_type") == "energy_cannon_hit", "StringName 必须转换为字符串")
	CombatTraceLogger.configure(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(trace_path))
	_finish()


## 累计一条测试断言结果。
## [param condition] 当前断言是否成立。
## [param message] 断言失败时输出的说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出测试汇总并以进程退出码表达成功或失败。
func _finish() -> void:
	if failures.is_empty():
		print("COMBAT_TRACE_LOGGER_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("COMBAT_TRACE_LOGGER_FAILED (%d failures)" % failures.size())
	quit(1)
