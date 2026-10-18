class_name TextureLruCache
extends RefCounted

var budget_bytes: int
var retained_bytes := 0
var _entries: Dictionary[String, Texture2D] = {}
var _costs: Dictionary[String, int] = {}
var _recent: Array[String] = []


## 建立仅供主线程使用的纹理引用缓存。
## [param budget] 缓存估算字节上限，不代表显存或进程总内存。
func _init(budget: int = 256 * 1024 * 1024) -> void:
	budget_bytes = maxi(0, budget)


## 命中后更新使用顺序，返回原纹理引用。
## [param path] 保持原样的资源路径。
## 返回缓存纹理，未命中返回 null。
func fetch(path: String) -> Texture2D:
	if not _entries.has(path): return null
	_recent.erase(path)
	_recent.append(path)
	return _entries[path]


## 保留成功上传的纹理，超预算仅释放缓存引用，活动精灵仍可使用它。
## [param path] 原资源路径。[param texture] 主线程创建的纹理。
func retain(path: String, texture: Texture2D) -> void:
	if texture == null: return
	_erase(path)
	# RGBA8 加完整 mip 链的保守估算；不为计量再次读回 GPU 图像。
	var cost := ceili(texture.get_width() * texture.get_height() * 4.0 * 4.0 / 3.0)
	if cost > budget_bytes: return
	while retained_bytes + cost > budget_bytes and not _recent.is_empty(): _erase(_recent[0])
	_entries[path] = texture
	_costs[path] = cost
	_recent.append(path)
	retained_bytes += cost
	PerformanceTelemetry.set_gauge(&"texture_cache_bytes", retained_bytes)


## 清空缓存，保留外部节点持有的纹理有效性。
func clear() -> void:
	_entries.clear()
	_costs.clear()
	_recent.clear()
	retained_bytes = 0


## 移除一个缓存引用并更新估算占用。
## [param path] 已有或不存在的资源路径。
func _erase(path: String) -> void:
	retained_bytes -= _costs.get(path, 0)
	_entries.erase(path)
	_costs.erase(path)
	_recent.erase(path)
