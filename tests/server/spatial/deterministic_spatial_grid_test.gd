extends SceneTree

const DeterministicSpatialGridScript := preload("res://scripts/core/deterministic_spatial_grid.gd")

var assertions := 0
var failures: Array[String] = []


## 运行空间索引边界、生命周期与确定性查询回归。
func _initialize() -> void:
	_test_cell_boundaries_and_cross_cell_updates()
	_test_duplicate_registration_and_removal()
	_test_death_release_and_map_switch_reuse()
	_test_deterministic_circle_and_aabb_queries()
	if failures.is_empty():
		print("DETERMINISTIC_SPATIAL_GRID_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 验证负坐标、精确边界与跨格更新不会留下旧位置。
func _test_cell_boundaries_and_cross_cell_updates() -> void:
	var grid = DeterministicSpatialGridScript.new(64.0)
	_expect(grid.cell_for_position(Vector2(63.99, -0.01)) == Vector2i(0, -1), "边界前位置应落入相邻负 y 单元")
	_expect(grid.cell_for_position(Vector2(64.0, 0.0)) == Vector2i(1, 0), "精确边界应落入右侧单元")
	_expect(grid.register("monster.a", Vector2(63.99, 0.0)), "首次登记应成功")
	_expect(grid.query_circle(Vector2(63.99, 0.0), 0.01) == ["monster.a"], "边界前实体应可查询")
	_expect(grid.update("monster.a", Vector2(128.0, 0.0)), "跨单元移动应成功")
	_expect(grid.query_circle(Vector2(63.99, 0.0), 0.01).is_empty(), "跨单元后旧位置不应残留")
	_expect(grid.query_circle(Vector2(128.0, 0.0), 0.01) == ["monster.a"], "跨单元后新位置应可查询")


## 验证重复登记不覆盖坐标，重复删除没有副作用。
func _test_duplicate_registration_and_removal() -> void:
	var grid = DeterministicSpatialGridScript.new(32.0)
	_expect(grid.register("duplicate", Vector2.ZERO), "实体首次登记应成功")
	_expect(not grid.register("duplicate", Vector2(32.0, 0.0)), "重复登记应被拒绝")
	_expect(grid.position_for("duplicate") == Vector2.ZERO, "重复登记不得覆盖原位置")
	_expect(not grid.update("missing", Vector2.ZERO), "未知实体更新应被拒绝")
	_expect(grid.remove("duplicate"), "已登记实体应可移除")
	_expect(not grid.remove("duplicate"), "重复移除应返回失败")
	_expect(grid.query_all().is_empty(), "移除后索引应为空")


## 验证同点命中排序、闭合边界与非法半径。
func _test_deterministic_circle_and_aabb_queries() -> void:
	var grid = DeterministicSpatialGridScript.new(16.0)
	for entity_id: String in ["entity.z", "entity.a", "entity.m"]:
		_expect(grid.register(entity_id, Vector2(8.0, 8.0)), "同点实体登记应成功")
	_expect(
		grid.query_circle(Vector2(8.0, 8.0), 0.0) == ["entity.a", "entity.m", "entity.z"],
		"同距离实体必须按稳定 ID 排序",
	)
	_expect(
		grid.query_aabb(Vector2.ZERO, Vector2(8.0, 8.0)) == ["entity.a", "entity.m", "entity.z"],
		"AABB 查询必须包含闭合边界并按稳定 ID 排序",
	)
	_expect(grid.query_circle(Vector2(8.0, 8.0), -1.0).is_empty(), "负半径查询应为空")


## 验证死亡清理及换图后同一编号能够重新登记。
func _test_death_release_and_map_switch_reuse() -> void:
	var grid = DeterministicSpatialGridScript.new(64.0)
	_expect(grid.register("monster.dead", Vector2(10.0, 10.0)), "死亡实体登记应成功")
	_expect(grid.remove("monster.dead"), "死亡实体应从索引释放")
	_expect(grid.query_all().is_empty(), "死亡实体释放后不应继续参与查询")
	_expect(grid.register("player.map_switch", Vector2(10.0, 10.0)), "地图切换前登记应成功")
	_expect(grid.remove("player.map_switch"), "地图切换时应释放旧地图归属")
	_expect(grid.register("player.map_switch", Vector2(640.0, 10.0)), "地图切换后同一 ID 可重新登记")
	_expect(
		grid.query_circle(Vector2(640.0, 10.0), 0.0) == ["player.map_switch"],
		"地图切换后实体只能出现在新位置",
	)


## 记录断言结果。
## [param condition] 预期为真的条件。
## [param message] 失败时的定位说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
