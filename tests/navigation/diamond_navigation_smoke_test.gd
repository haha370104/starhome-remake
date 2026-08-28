extends SceneTree

const DiamondNavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")
const GLORY_HALL_GRID := "res://assets/maps/yian_harbor/hall_floor_1/navigation_grid.bin"

var failures: PackedStringArray = []


## 加载荣耀版大厅导航数据并验证关键可达性、阻挡与寻路约束。
## 设计：该入口同时承担测试夹具初始化和进程退出码汇总，保持无外部测试框架依赖。
func _initialize() -> void:
	var navigation: DiamondNavigation = DiamondNavigationScript.new()
	_expect(
		navigation.load_from(GLORY_HALL_GRID, Vector2i(41, 320), Vector2(48, 12)),
		"荣耀版大厅导航应按配置尺寸加载",
	)
	_expect(navigation.data.size() == 13120, "导航字节数应为 41×320")
	_expect(navigation.is_walkable(Vector2(730, 1330)), "玩家出生区域应可行走")
	_expect(not navigation.is_walkable(Vector2(960, 900)), "中央平台阻挡区应不可行走")
	_expect(
		navigation.world_to_cell(navigation.cell_to_world(Vector2i(20, 100))) == Vector2i(20, 100),
		"菱形网格中心坐标应可无损往返",
	)
	var path := navigation.find_path(Vector2(730, 1330), Vector2(960, 1000))
	_expect(path.size() >= 2, "两个可达点之间应生成路径")
	var nearest := navigation.closest_reachable_position(Vector2(730, 1330), Vector2(960, 900))
	_expect(nearest.is_finite(), "阻挡目标附近应找到连通的可达点")
	_expect(navigation.is_walkable(nearest), "阻挡目标的回退点必须可行走")
	var spawn_fallback := navigation.closest_walkable_position(Vector2(965, 920))
	_expect(spawn_fallback.is_finite(), "旧配置中的阻挡出生点应能吸附到荣耀版可达格")
	_expect(navigation.is_walkable(spawn_fallback), "出生点吸附结果必须可行走")

	if failures.is_empty():
		print("DIAMOND_NAVIGATION_SMOKE_OK (10 assertions)")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
