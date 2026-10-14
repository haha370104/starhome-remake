class_name MapNavigationCache
extends RefCounted

const CAPACITY := 2
static var _domains: Dictionary = {}
var _entries: Dictionary[String, DiamondNavigation] = {}
var _recent: Array[String] = []


## 按运行侧隔离缓存，避免本地客户端与权威端共享可变寻路图。
## [param side] client 或 server；返回该侧最近两张图的缓存。
static func for_side(side: StringName) -> MapNavigationCache:
	if not _domains.has(side): _domains[side] = MapNavigationCache.new()
	return _domains[side]


## 复用导航图；只有成功读取后才替换旧条目，容量仅约束缓存持有的引用。
## [param path] 导航字节路径。[param dimensions] 网格宽高。[param cells] 菱形单元尺寸。
## 返回导航，失败返回 null；寻路图只在所属侧主线程使用。
func acquire(path: String, dimensions: Vector2i, cells: Vector2) -> DiamondNavigation:
	var key := "%s|%s|%s" % [path, dimensions, cells]
	if _entries.has(key):
		_recent.erase(key)
		_recent.append(key)
		PerformanceTelemetry.increment(&"navigation_cache_hit")
		return _entries[key]
	var _timing := PerformanceTelemetry.measure(&"navigation_build")
	var navigation := DiamondNavigation.new()
	if not navigation.load_from(path, dimensions, cells): return null
	_entries[key] = navigation
	_recent.append(key)
	while _recent.size() > CAPACITY: _entries.erase(_recent.pop_front())
	PerformanceTelemetry.increment(&"navigation_cache_miss")
	return navigation


## 清除缓存持有的引用，不销毁仍由活动场景持有的导航。
func clear() -> void:
	_entries.clear()
	_recent.clear()


## 返回缓存条目数，供资源预算与回归检查。
func size() -> int:
	return _entries.size()
