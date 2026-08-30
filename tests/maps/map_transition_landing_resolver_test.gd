extends SceneTree

const LoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const ResolverScript := preload("res://scripts/maps/map_transition_landing_resolver.gd")

var failures: PackedStringArray = []
var assertions := 0


## 验证相邻野外地图使用反向出口落点，而不是共享的地图中心默认出生点。
func _initialize() -> void:
	var loader = LoaderScript.new()
	var d04: MapDefinition = loader.load_file("res://data/maps/d04_field_zone.json")
	var c04: MapDefinition = loader.load_file("res://data/maps/buli_c04_field_zone.json")
	var c03: MapDefinition = loader.load_file("res://data/maps/buli_c03_field_zone.json")
	var city: MapDefinition = loader.load_file("res://data/maps/yian_harbor_city.json")
	_expect(d04 != null and c04 != null and c03 != null and city != null, "测试地图定义必须完整")
	if d04 == null or c04 == null or c03 == null or city == null:
		_finish()
		return
	_test_landing(
		d04,
		d04.transition_by_id(&"exit_to_c04_field"),
		c04,
		Vector2(4687, 2525),
		&"exit_to_d04",
	)
	_test_landing(
		c04,
		c04.transition_by_id(&"exit_to_c03"),
		c03,
		Vector2(2426, 4565),
		&"exit_to_c04_field",
	)
	_test_landing(
		city,
		city.transition_by_id(&"exit_to_d04_northwest_gate"),
		d04,
		Vector2(1290, 2562),
		&"enter_city_via_northwest_gate",
	)
	_finish()


## 验证一条来源出口准确落到目标地图对应的反向出口接近点。
## [param source] 来源地图定义。
## [param transition] 来源地图出口。
## [param destination] 目标地图定义。
## [param expected_position] 预期连续落点。
## [param expected_reciprocal_id] 预期反向出口 ID。
func _test_landing(
	source: MapDefinition,
	transition: MapTransition,
	destination: MapDefinition,
	expected_position: Vector2,
	expected_reciprocal_id: StringName,
) -> void:
	var result: Dictionary = ResolverScript.resolve_landing(source, transition, destination)
	_expect(not result.is_empty(), "连续落点必须可解析：%s" % transition.transition_id)
	if result.is_empty():
		return
	_expect(result.get("evidence") == "reciprocal_exit", "相邻地图不得回退到中心出生点")
	_expect(result.get("position") == expected_position, "反向出口落点错误：%s" % transition.transition_id)
	_expect(
		result.get("reciprocal_transition_id") == expected_reciprocal_id,
		"反向出口选择错误：%s" % transition.transition_id,
	)


## 汇总连续传送断言并设置进程退出码。
func _finish() -> void:
	if failures.is_empty():
		print("MAP_TRANSITION_LANDING_RESOLVER_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 记录一条连续传送断言。
## [param condition] 连续落点约束是否满足。
## [param message] 断言失败时输出的诊断文本。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
