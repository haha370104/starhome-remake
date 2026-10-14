extends SceneTree

var checks := 0
var failures: Array[String] = []


## 以固定随机种子对照矩形索引和旧全遍历结果，验证边界及删除。
func _initialize() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 73
	var index := SpatialBoundsIndex.new()
	var rectangles: Dictionary[String, Rect2] = {}
	for number in 150:
		var id := str(number)
		var bounds := Rect2(random.randf_range(-1000, 1000), random.randf_range(-1000, 1000), random.randf_range(10, 500), random.randf_range(10, 200))
		index.update(id, bounds)
		rectangles[id] = bounds
	for sample in 300:
		var point := Vector2(random.randf_range(-1200, 1200), random.randf_range(-1200, 1200))
		var expected: Array[String] = []
		for id: String in rectangles:
			if rectangles[id].has_point(point): expected.append(id)
		_check(index.at_point(point) == expected, "矩形索引与原遍历顺序一致 %d" % sample)
	index.update("0", Rect2(-2000, -2000, 20, 20))
	_check(index.at_point(Vector2(-1995, -1995)) == ["0"], "跨桶移动更新")
	index.remove("0")
	_check(index.at_point(Vector2(-1995, -1995)).is_empty(), "删除不残留索引")
	_test_obstacles(random)
	print("World query indexes: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 对照原逐格判定，确认动态障碍只优化候选，不改变禁用格或预留目标。
## [param random] 固定种子随机源。
func _test_obstacles(random: RandomNumberGenerator) -> void:
	var bytes := PackedByteArray()
	bytes.resize(40 * 120)
	bytes.fill(1)
	var file := FileAccess.open("user://obstacle_grid.bin", FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var navigation := DiamondNavigation.new()
	_check(navigation.load_from("user://obstacle_grid.bin", Vector2i(40, 120), Vector2(48, 12)), "导航加载")
	var entities: Dictionary = {}
	for number in 25:
		var entity := AuthoritativeEntity.new()
		entity.entity_id = str(number)
		entity.position = Vector2(random.randf_range(0, 1800), random.randf_range(0, 1400))
		entity.target_position = entity.position + Vector2(60, 20)
		entities[entity.entity_id] = entity
	var obstacles := EntityObstacleIndex.new()
	obstacles.refresh(entities)
	for radius: float in [4.0, 18.0, 70.0]:
		var expected: Array[int] = []
		for point_id: int in navigation.graph.get_point_ids():
			if point_id == 0: continue
			for id: String in entities:
				if id == "0": continue
				if navigation.graph.get_point_position(point_id).distance_squared_to(entities[id].position) < radius * radius:
					expected.append(point_id)
					break
		var actual := obstacles.block_navigation(navigation, entities, "0", radius, 0)
		actual.sort()
		expected.sort()
		_check(actual == expected, "动态禁用格与旧算法一致 radius=%s" % radius)
		for id: int in actual: navigation.graph.set_point_disabled(id, false)
	var subject: AuthoritativeEntity = entities["1"]
	_check("1" in obstacles.nearby(subject.target_position, 1, true), "预留目的地参与避让")
	_check("1" not in obstacles.nearby(subject.target_position, 1, false), "无需预留时仅查询脚点")
	subject.position = Vector2(-500, -500)
	obstacles.update(subject)
	_check(obstacles.nearby(subject.position, 1, false) == ["1"], "同帧已移动实体更新")


## 汇总索引等价性断言。
## [param condition] 实际结果。[param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
