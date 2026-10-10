class_name AleSpriteRepository
extends RefCounted

const TextureLoaderScript := preload("res://scripts/content/runtime_texture_loader.gd")
const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")
const DEFAULT_INDEX_PATH := "res://data/content/glory_sprite_runtime_index_v1.json"
const DEFAULT_PALETTE_INDEX_PATH := "res://data/content/glory_monster_palette_runtime_index_v1.json"
const DEFAULT_MINE_PALETTE_INDEX_PATH := "res://data/content/glory_mine_palette_runtime_index_v1.json"
const DEFAULT_RECOVERED_INDEX_PATH := "res://data/content/recovered_sprite_runtime_index_v1.json"
const DEFAULT_CACHE_BUDGET_BYTES := 256 * 1024 * 1024
const ANIMATION_FRAME_ESTIMATE_BYTES := 256
const SPRITE_FRAME_ESTIMATE_BYTES := 128
const METADATA_ESTIMATE_BYTES := 64

var content_version := ""
var errors: PackedStringArray = []
var _by_logical_id: Dictionary = {}
var _logical_ids_by_basename: Dictionary = {}
var _animation_cache: Dictionary = {}
var _metadata_cache: Dictionary = {}
var _sprite_frames_cache: Dictionary = {}

class AnimationBuild extends RefCounted:
	var definition: Dictionary
	var metadata: Dictionary
	var frames: Array[Dictionary] = []
	var bounds := Rect2()
	var failed := false
var _page_cache: Dictionary = {}
var cache_budget_bytes := DEFAULT_CACHE_BUDGET_BYTES
var _cache_entries: Dictionary = {}
var _cache_evicted_keys: Dictionary = {}
var _pinned_cache_keys: Dictionary = {}
var _active_map_animation_ids: PackedStringArray = []
var _cache_used_bytes := 0
var _cache_clock := 0
var _cache_stats := {"hits": 0, "misses": 0, "evictions": 0, "reloads": 0}


## 加载 ALE 逻辑路径索引；图片和帧描述仍保持按需读取。
## 返回该函数计算、查询或操作得到的结果。
func load_default() -> bool:
	if not load_file(DEFAULT_INDEX_PATH):
		return false
	if not merge_file(DEFAULT_PALETTE_INDEX_PATH):
		return false
	if not merge_file(DEFAULT_MINE_PALETTE_INDEX_PATH):
		return false
	return merge_file(DEFAULT_RECOVERED_INDEX_PATH)


## 加载并校验 `load_file` 对应的模块数据。
## [param path] 调用方传入的 `path` 参数。
## 返回该函数计算、查询或操作得到的结果。
func load_file(path: String) -> bool:
	errors.clear()
	_by_logical_id.clear()
	_logical_ids_by_basename.clear()
	_animation_cache.clear()
	_metadata_cache.clear()
	_sprite_frames_cache.clear()
	_page_cache.clear()
	_cache_entries.clear()
	_cache_evicted_keys.clear()
	_pinned_cache_keys.clear()
	_active_map_animation_ids.clear()
	_cache_used_bytes = 0
	_cache_clock = 0
	_cache_stats = {"hits": 0, "misses": 0, "evictions": 0, "reloads": 0}
	return _merge_file(path)


## 执行 `merge_file` 对应的模块操作。
## [param path] 调用方传入的 `path` 参数。
## 返回该函数计算、查询或操作得到的结果。
func merge_file(path: String) -> bool:
	errors.clear()
	return _merge_file(path)


## 执行 `merge_file` 对应的模块操作。
## [param path] 调用方传入的 `path` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _merge_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		_add_error("index", "ALE 精灵索引不存在：%s" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		_add_error("index", "ALE 精灵索引格式无效")
		return false
	content_version = String(parsed.get("content_version", ""))
	var rows: Variant = parsed.get("sprites", [])
	if content_version.is_empty() or not rows is Array:
		_add_error("index", "ALE 精灵索引缺少版本或 rows")
		return false
	for row_value: Variant in rows:
		if not row_value is Dictionary:
			_add_error("row", "ALE 精灵条目必须是 object")
			continue
		var row: Dictionary = row_value
		var logical_id := normalize_reference(String(row.get("logical_id", "")))
		var frames_path := String(row.get("frames_path", ""))
		var allowed_path := frames_path.begins_with("res://assets/glory/") or frames_path.begins_with("res://assets/recovered/")
		if logical_id.is_empty() or not allowed_path or frames_path.contains(".."):
			_add_error("row", "ALE 精灵条目路径无效")
			continue
		if _by_logical_id.has(logical_id):
			_add_error("row", "ALE 逻辑路径重复：%s" % logical_id)
			continue
		_by_logical_id[logical_id] = row.duplicate(true)
		var basename := logical_id.get_file()
		var basename_ids: PackedStringArray = _logical_ids_by_basename.get(
			basename, PackedStringArray()
		)
		basename_ids.append(logical_id)
		_logical_ids_by_basename[basename] = basename_ids
	return errors.is_empty()


## 将旧 FCC 中的 ../pic2/foo.ale、反斜杠和大小写归一为索引键。
## [param asset_reference] 原始资源逻辑路径或文件名。
## 返回该函数计算、查询或操作得到的结果。
static func normalize_reference(asset_reference: String) -> String:
	var normalized := asset_reference.strip_edges().replace("\\", "/").to_lower()
	while normalized.contains("//"):
		normalized = normalized.replace("//", "/")
	while normalized.begins_with("../"):
		normalized = normalized.trim_prefix("../")
	while normalized.begins_with("./"):
		normalized = normalized.trim_prefix("./")
	if normalized.ends_with(".ale"):
		normalized = normalized.left(-4)
	while normalized.begins_with("/"):
		normalized = normalized.trim_prefix("/")
	while normalized.ends_with("/"):
		normalized = normalized.trim_suffix("/")
	return normalized.strip_edges()


## 优先解析完整路径；裸文件名仅在唯一或命中指定前缀时成立。
## [param asset_reference] 原始资源逻辑路径或文件名。
## [param preferred_prefix] 调用方传入的 `preferred_prefix` 参数。
## 返回该函数计算、查询或操作得到的结果。
func resolve(asset_reference: String, preferred_prefix := "") -> Dictionary:
	var normalized := normalize_reference(asset_reference)
	if _by_logical_id.has(normalized):
		return (_by_logical_id[normalized] as Dictionary).duplicate(true)
	if normalized.contains("/"):
		return {}
	var candidates: PackedStringArray = _logical_ids_by_basename.get(normalized, PackedStringArray())
	if not preferred_prefix.is_empty():
		var prefix := normalize_reference(preferred_prefix) + "/"
		for candidate in candidates:
			if candidate.begins_with(prefix):
				return (_by_logical_id[candidate] as Dictionary).duplicate(true)
	if candidates.size() == 1:
		return (_by_logical_id[candidates[0]] as Dictionary).duplicate(true)
	return {}


## 执行 `size` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func size() -> int:
	return _by_logical_id.size()


## 返回帧描述、页贴图和原点，可直接供 AnimatedSprite2D 表现适配器消费。
## 加载并校验 `load_animation` 对应的模块数据。
## [param asset_reference] 原始资源逻辑路径或文件名。
## [param preferred_prefix] 调用方传入的 `preferred_prefix` 参数。
func load_animation(asset_reference: String, preferred_prefix := "") -> Dictionary:
	var definition := resolve(asset_reference, preferred_prefix)
	if definition.is_empty(): return {}
	var logical_id := String(definition.logical_id)
	if _animation_cache.has(logical_id):
		_cache_hit("animation", logical_id)
		return _animation_cache[logical_id]
	_cache_miss()
	var metadata: Dictionary = _metadata_cache.get(logical_id, {})
	if metadata.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(definition.frames_path)))
		if not parsed is Dictionary: return {}
		metadata = parsed
		_metadata_cache[logical_id] = metadata
		_store_cache("metadata", logical_id, _estimate_metadata_bytes(metadata))
	else:
		_cache_hit("metadata", logical_id)
	for path: String in definition.get("page_paths", []):
		if cached_page(path) != null: continue
		_cache_miss()
		var texture := TextureLoaderScript.load_texture(path)
		if texture == null: return {}
		cache_page(path, texture, true)
	var build := begin_animation(definition, metadata)
	advance_animation(build, 0)
	return cached_animation(logical_id)


## 查询已经构造完成的动画，不创建新帧或读取文件。
## [param logical_id] 解析后的资源身份。
## 返回共享只读动画，未就绪为空。
func cached_animation(logical_id: String) -> Dictionary:
	if not _animation_cache.has(logical_id):
		return {}
	_cache_touch("animation", logical_id)
	return _animation_cache[logical_id]


## 主线程准备动画构造；同步与异步调用共用相同帧算法。
## [param definition] 索引条目。[param metadata] 已解码的帧描述。
## 返回尚未构造 GPU 帧视图的工作对象。
func begin_animation(definition: Dictionary, metadata: Dictionary) -> AnimationBuild:
	var build := AnimationBuild.new()
	build.definition = definition
	build.metadata = metadata
	_metadata_cache[String(definition.logical_id)] = metadata
	_store_cache("metadata", String(definition.logical_id), _estimate_metadata_bytes(metadata))
	return build


## 按时间预算构造 AtlasTexture，完成后写入共享动画缓存。
## [param build] 主线程工作对象。[param budget_usec] 微秒预算，零为同步构造。
## 返回是否完成；格式错误保存在 failed，缓存中不会出现半成品。
func advance_animation(build: AnimationBuild, budget_usec: int = 1000) -> bool:
	var started := Time.get_ticks_usec()
	var rows: Array = build.metadata.get("frames", [])
	while build.frames.size() < rows.size():
		var row: Variant = rows[build.frames.size()]
		if not row is Dictionary:
			build.failed = true
			return true
		var page := int(row.get("page", -1))
		var paths: Array = build.definition.get("page_paths", [])
		if page < 0 or page >= paths.size() or not _page_cache.has(paths[page]):
			build.failed = true
			return true
		var atlas := AtlasTexture.new()
		atlas.atlas = _page_cache[paths[page]]
		atlas.region = Rect2(float(row.get("x", 0)), float(row.get("y", 0)), float(row.get("width", 0)), float(row.get("height", 0)))
		var origin := Vector2(float(row.get("origin_x", 0)), float(row.get("origin_y", 0)))
		var bounds := Rect2(origin, atlas.region.size)
		build.bounds = bounds if build.frames.is_empty() else build.bounds.merge(bounds)
		build.frames.append({"index": int(row.get("index", build.frames.size())), "texture": atlas, "origin": origin, "size": atlas.region.size})
		if budget_usec > 0 and Time.get_ticks_usec() - started >= budget_usec: return false
	var logical_id := String(build.definition.logical_id)
	_animation_cache[logical_id] = {"logical_id": build.definition.logical_id,
		"frames": build.frames, "cell_size": Vector2(float(build.metadata.get("cell_width", 0)), float(build.metadata.get("cell_height", 0))),
		"bounds_origin": build.bounds.position, "bounds_size": build.bounds.size,
		"source_release": build.definition.get("source_release", "starhome_lz_ry")}
	_store_cache("animation", logical_id, _estimate_animation_bytes(build))
	return true


## 把导入纹理放入同一页缓存，直接图片和 ALE 不重复上传同一路径。
## [param path] 资源路径。[param texture] 主线程就绪的纹理。[param lookup_recorded] 调用方是否已经记录缺页。
func cache_page(path: String, texture: Texture2D, lookup_recorded := false) -> void:
	if not _page_cache.has(path) and not lookup_recorded:
		_cache_miss()
	_page_cache[path] = texture
	_store_cache("page", path, _estimate_texture_bytes(texture))


## 工作线程读取动画描述和缺失的图集页；不触碰仓储可变缓存。
## [param request] 包含隔离定义、元数据和已缓存页路径的请求。
## 返回纯 CPU 结果，错误时为空。
static func read_animation_source(request: Dictionary) -> Dictionary:
	var definition: Dictionary = request.definition
	var metadata: Dictionary = request.get("metadata", {})
	if metadata.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(definition.frames_path)))
		if not parsed is Dictionary: return {}
		metadata = parsed
	var images: Dictionary = {}
	for path: String in definition.get("page_paths", []):
		if request.cached_pages.has(path): continue
		var image := RuntimeTextureLoader.read_image(path)
		if image == null or image.is_empty(): return {}
		images[path] = image
	return {"definition": definition, "metadata": metadata, "images": images}


## 执行 `add_error` 对应的模块操作。
## [param field] 调用方传入的 `field` 参数。
## [param message] 调用方传入的 `message` 参数。
func _add_error(field: String, message: String) -> void:
	errors.append("%s: %s" % [field, message])


## 提供工作线程可读取的隔离元数据，不暴露可变缓存。
## [param logical_id] 素材稳定身份。
## 返回元数据副本，未加载时为空。
func cached_metadata(logical_id: String) -> Dictionary:
	if not _metadata_cache.has(logical_id):
		return {}
	_cache_touch("metadata", logical_id)
	return (_metadata_cache[logical_id] as Dictionary).duplicate(true)


## 提供已经上传的图集路径，避免后台重复解码。
## 返回路径数组副本。
func cached_pages() -> Array:
	return _page_cache.keys()


func cached_page(path: String) -> Texture2D:
	if not _page_cache.has(path):
		return null
	_cache_hit("page", path)
	return _page_cache[path] as Texture2D


func configure_cache_budget(bytes: int) -> void:
	cache_budget_bytes = maxi(1, bytes)
	_enforce_cache_budget()


func cache_stats() -> Dictionary:
	return {
		"budget_bytes": cache_budget_bytes,
		"used_bytes": _cache_used_bytes,
		"entry_count": _cache_entries.size(),
		"hits": int(_cache_stats.hits),
		"misses": int(_cache_stats.misses),
		"evictions": int(_cache_stats.evictions),
		"reloads": int(_cache_stats.reloads),
	}


func load_sprite_frames(asset_reference: String, preferred_prefix := "") -> SpriteFrames:
	var definition := resolve(asset_reference, preferred_prefix)
	if definition.is_empty(): return null
	var logical_id := String(definition.logical_id)
	if _sprite_frames_cache.has(logical_id):
		_cache_hit("sprite_frames", logical_id)
		return _sprite_frames_cache[logical_id] as SpriteFrames
	_cache_miss()
	var animation := load_animation(asset_reference, preferred_prefix)
	var source_frames: Array = animation.get("frames", [])
	if source_frames.is_empty(): return null
	var frames := SpriteFrames.new()
	frames.add_animation(&"raw")
	frames.set_animation_speed(&"raw", 10.0)
	var origins: Array[Vector2] = []
	for frame: Dictionary in source_frames:
		frames.add_frame(&"raw", frame["texture"])
		origins.append(frame["origin"])
	frames.set_meta("ale_origins", origins)
	_sprite_frames_cache[logical_id] = frames
	_store_cache("sprite_frames", logical_id, source_frames.size() * SPRITE_FRAME_ESTIMATE_BYTES)
	return frames


func retain_animation(logical_id: String) -> void:
	_retain_cache_key(_cache_key("animation", logical_id))
	var definition: Dictionary = _by_logical_id.get(logical_id, {})
	for path: String in definition.get("page_paths", []):
		_retain_cache_key(_cache_key("page", path))


func release_animation(logical_id: String) -> void:
	_release_cache_key(_cache_key("animation", logical_id))
	var definition: Dictionary = _by_logical_id.get(logical_id, {})
	for path: String in definition.get("page_paths", []):
		_release_cache_key(_cache_key("page", path))
	_enforce_cache_budget()


func retain_page(path: String) -> void:
	_retain_cache_key(_cache_key("page", path))


func release_page(path: String) -> void:
	_release_cache_key(_cache_key("page", path))
	_enforce_cache_budget()


func set_active_map_references(references: Array, preferred_prefix := "") -> void:
	for logical_id: String in _active_map_animation_ids:
		release_animation(logical_id)
	_active_map_animation_ids.clear()
	for asset_reference: String in references:
		var definition := resolve(asset_reference, preferred_prefix)
		var logical_id := String(definition.get("logical_id", ""))
		if logical_id.is_empty() or _active_map_animation_ids.has(logical_id): continue
		_active_map_animation_ids.append(logical_id)
		retain_animation(logical_id)


func clear_active_map_references() -> void:
	set_active_map_references([])


## 读取单帧描述；只涉及CPU数据，可在工作线程执行。
## [param request] 含路径或已解析定义、帧序号和可选缓存元数据的隔离请求。
## 返回目标图集、帧矩形、原点和元数据；错误时为空。
static func read_frame_source(request: Dictionary) -> Dictionary:
	var path := String(request.get("path", ""))
	if not path.is_empty() and FileAccess.file_exists(path):
		return {"path": path, "origin": Vector2.ZERO}
	var definition: Dictionary = request.get("definition", {})
	if definition.is_empty(): return {}
	var metadata: Dictionary = request.get("metadata", {})
	if metadata.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(definition.frames_path)))
		if not parsed is Dictionary: return {}
		metadata = parsed
	var frames: Array = metadata.get("frames", [])
	if frames.is_empty(): return {}
	var frame: Dictionary = frames[clampi(int(request.get("frame", 0)), 0, frames.size() - 1)]
	var page := int(frame.get("page", -1))
	var pages: Array = definition.get("page_paths", [])
	if page < 0 or page >= pages.size(): return {}
	return {"path": String(pages[page]), "logical_id": String(definition.logical_id), "metadata": metadata,
		"region": Rect2(float(frame.x), float(frame.y), float(frame.width), float(frame.height)),
		"origin": Vector2(float(frame.get("origin_x", 0)), float(frame.get("origin_y", 0)))}


## 在主线程上传目标图集并创建一个帧视图，与动画共用页缓存。
## [param source] 后台读取的帧描述和可选CPU图像。
## 返回图标、原点和原生尺寸，读取失败时为空。
func finish_frame(source: Dictionary) -> Dictionary:
	if source.is_empty(): return {}
	var path := String(source.path)
	var texture := cached_page(path)
	if texture == null:
		var image: Image = source.get("image")
		if image == null or image.is_empty(): return {}
		_cache_miss()
		texture = ImageTexture.create_from_image(image)
		cache_page(path, texture, true)
	if source.has("metadata"):
		var logical_id := String(source.logical_id)
		_metadata_cache[logical_id] = source.metadata
		_store_cache("metadata", logical_id, _estimate_metadata_bytes(source.metadata))
	if source.has("region"):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = source.region
		texture = atlas
	return {"texture": texture, "origin": source.origin, "size": texture.get_size()}


## 同步调用方也只读取所需帧，不构建整段动画。
## [param asset_reference] ALE逻辑身份。[param index] 帧序号。
## 返回共享图集上的单帧视图。
func load_frame(asset_reference: String, index: int) -> Dictionary:
	var definition := resolve(asset_reference)
	var source := read_frame_source({"definition": definition, "frame": index,
		"metadata": cached_metadata(String(definition.get("logical_id", "")))})
	if source.is_empty(): return {}
	if not _page_cache.has(String(source.path)): source["image"] = TextureLoaderScript.read_image(String(source.path))
	return finish_frame(source)


func _cache_key(kind: String, cache_id: String) -> String:
	return "%s:%s" % [kind, cache_id]


func _store_cache(kind: String, cache_id: String, bytes: int) -> void:
	var key := _cache_key(kind, cache_id)
	var previous: Dictionary = _cache_entries.get(key, {})
	if not previous.is_empty():
		_cache_used_bytes -= int(previous.get("bytes", 0))
	if _cache_evicted_keys.has(key):
		_cache_stats.reloads = int(_cache_stats.reloads) + 1
		_cache_evicted_keys.erase(key)
	_cache_clock += 1
	_cache_entries[key] = {"kind": kind, "id": cache_id, "bytes": maxi(1, bytes), "last_used": _cache_clock}
	_cache_used_bytes += maxi(1, bytes)
	_update_cache_gauges()
	_enforce_cache_budget()


func _cache_touch(kind: String, cache_id: String) -> void:
	_cache_touch_key(_cache_key(kind, cache_id))


func _cache_touch_key(key: String) -> void:
	if not _cache_entries.has(key):
		return
	_cache_clock += 1
	_cache_entries[key].last_used = _cache_clock


func _cache_hit(kind: String, cache_id: String) -> void:
	_cache_stats.hits = int(_cache_stats.hits) + 1
	_cache_touch(kind, cache_id)
	PerformanceTelemetryScript.increment(&"resource_cache_hits")


func _cache_miss() -> void:
	_cache_stats.misses = int(_cache_stats.misses) + 1
	PerformanceTelemetryScript.increment(&"resource_cache_misses")


func _retain_cache_key(key: String) -> void:
	_pinned_cache_keys[key] = true
	if _cache_entries.has(key):
		_cache_touch_key(key)


func _release_cache_key(key: String) -> void:
	_pinned_cache_keys.erase(key)


func _enforce_cache_budget() -> void:
	while _cache_used_bytes > cache_budget_bytes:
		var oldest_key := ""
		var oldest_tick := INF
		for key: String in _cache_entries:
			if _pinned_cache_keys.has(key):
				continue
			if String(_cache_entries[key].get("kind", "")) == "page" and _is_page_referenced(String(_cache_entries[key].get("id", ""))):
				continue
			var last_used := int(_cache_entries[key].get("last_used", 0))
			if last_used < oldest_tick:
				oldest_tick = last_used
				oldest_key = key
		if oldest_key.is_empty():
			break
		_evict_cache_key(oldest_key)
	_update_cache_gauges()


func _evict_cache_key(key: String) -> void:
	var entry: Dictionary = _cache_entries.get(key, {})
	if entry.is_empty():
		return
	_cache_used_bytes -= int(entry.get("bytes", 0))
	_cache_entries.erase(key)
	_cache_evicted_keys[key] = true
	_cache_stats.evictions = int(_cache_stats.evictions) + 1
	var kind := String(entry.get("kind", ""))
	var cache_id := String(entry.get("id", ""))
	match kind:
		"page": _page_cache.erase(cache_id)
		"metadata": _metadata_cache.erase(cache_id)
		"animation":
			_animation_cache.erase(cache_id)
			var sprite_frames_key := _cache_key("sprite_frames", cache_id)
			if _cache_entries.has(sprite_frames_key): _evict_cache_key(sprite_frames_key)
			_sprite_frames_cache.erase(cache_id)
		"sprite_frames": _sprite_frames_cache.erase(cache_id)
		"visual": _sprite_frames_cache.erase(cache_id)
	PerformanceTelemetryScript.increment(&"resource_cache_evictions")


func _estimate_texture_bytes(texture: Texture2D) -> int:
	if texture == null:
		return 1
	return maxi(1, ceili(texture.get_width() * texture.get_height() * 16.0 / 3.0))


func _estimate_metadata_bytes(metadata: Dictionary) -> int:
	return maxi(METADATA_ESTIMATE_BYTES, JSON.stringify(metadata).length())


func _estimate_animation_bytes(build: AnimationBuild) -> int:
	return maxi(ANIMATION_FRAME_ESTIMATE_BYTES, build.frames.size() * ANIMATION_FRAME_ESTIMATE_BYTES)


func _is_page_referenced(path: String) -> bool:
	for logical_id: String in _animation_cache:
		var definition: Dictionary = _by_logical_id.get(logical_id, {})
		if path in definition.get("page_paths", []):
			return true
	return false


func _update_cache_gauges() -> void:
	PerformanceTelemetryScript.set_gauge(&"resource_cache_used_bytes", _cache_used_bytes)
	PerformanceTelemetryScript.set_gauge(&"resource_cache_budget_bytes", cache_budget_bytes)
	PerformanceTelemetryScript.set_gauge(&"resource_cache_entries", _cache_entries.size())
