class_name MapNavigationCache
extends RefCounted

const MAX_MAPS := 2
var _entries: Dictionary = {}


## 复用本所有者最近使用的导航；文件或网格配置变化时重新构建。
## [param path] 导航文件。[param grid_size] 网格大小。[param cell_size] 单元尺寸。
## 返回独立于其他缓存所有者的导航，读取失败返回 null。
## 设计：客户端和每个服务器各持有一个缓存，禁止共享可变的 AStar 图。
func acquire(path: String, grid_size: Vector2i, cell_size: Vector2, prepared: DiamondNavigation = null) -> DiamondNavigation:
	var signature := [grid_size, cell_size, FileAccess.get_modified_time(path)]
	var entry: Dictionary = _entries.get(path, {})
	if prepared != null or entry.get("signature") != signature:
		var navigation := prepared if prepared != null else DiamondNavigation.new()
		if prepared == null and not navigation.load_from(path, grid_size, cell_size):
			return null
		entry = {"signature": signature, "navigation": navigation}
	_entries.erase(path)
	_entries[path] = entry
	while _entries.size() > MAX_MAPS:
		_entries.erase(_entries.keys()[0])
	return entry.navigation
