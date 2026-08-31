extends SceneTree

const Planner := preload("res://scripts/navigation/monster_route_planner.gd")
const Loader := preload("res://scripts/maps/map_definition_loader.gd")

class CountingNavigation extends DiamondNavigation:
	var line_checks := 0
	var astar_requests := 0

	## 记录可见性查询次数后使用真实地图碰撞。
	## [param start] 路线起点。
	## [param target] 路线终点。
	## 返回整条线段是否可走。
	func segment_is_walkable(start: Vector2, target: Vector2) -> bool:
		line_checks += 1
		return super.segment_is_walkable(start, target)

	## 记录实际 AStar 请求，验证直线路径能直接通过。
	## [param start] 路线起点。
	## [param target] 路线终点。
	## [param should_simplify] 是否使用原有玩家路径简化。
	## 返回真实地图计算的路线。
	func find_path(start: Vector2, target: Vector2, should_simplify := true) -> PackedVector2Array:
		astar_requests += 1
		return super.find_path(start, target, should_simplify)

var failures := PackedStringArray()
var assertions := 0


## 在出现过百毫秒尖峰的真实 D03 障碍上验证完整、安全且有界的怪物路线。
func _initialize() -> void:
	var definition := Loader.new().load_file("res://data/maps/buli_d03_field_zone.json")
	var navigation := CountingNavigation.new()
	_expect(navigation.load_from(definition.navigation_data_path,
		definition.navigation_grid_size, definition.navigation_cell_size), "D03 navigation should load")
	var start := Vector2(2399.227, 1741.084)
	var target := Vector2(2232, 1884)
	var raw := navigation.find_path(start, target, false)
	_expect(raw.size() > 200, "fixture should retain the long obstacle detour")
	navigation.line_checks = 0
	var before := Time.get_ticks_usec()
	var result := Planner.resolve(navigation, "fixture", start, target)
	var elapsed := Time.get_ticks_usec() - before
	var queries := navigation.line_checks
	var path: PackedVector2Array = result.get("path", PackedVector2Array())
	_expect(path.size() >= 2, "detour should produce a route")
	if path.size() >= 2:
		_expect(path[0] == start and path[-1] == target, "smoothing must preserve exact endpoints")
		for index in range(1, path.size()):
			_expect(navigation.segment_is_walkable(path[index - 1], path[index]), "every smoothed segment must avoid obstacles")
	_expect(queries <= 24 * raw.size(), "visibility queries must stay within the per-anchor lookahead bound")
	print("LONG_MONSTER_ROUTE points=%d -> %d line_checks=%d elapsed_ms=%.3f" % [raw.size(), path.size(), queries, elapsed / 1000.0])
	navigation.astar_requests = 0
	var direct := Planner.resolve(navigation, "fixture", Vector2(2304, 1776), Vector2(2328, 1788))
	_expect(direct.get("path", []).size() == 2 and navigation.astar_requests == 0, "clear straight segments should bypass AStar")
	_expect(Planner.resolve(navigation, "fixture", Vector2.INF, target).is_empty(), "nonfinite coordinates must be rejected")
	if failures.is_empty():
		print("MONSTER_ROUTE_PLANNER_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 汇总一项路线安全或复杂度断言。
## [param condition] 要求成立的条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
