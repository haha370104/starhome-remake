class_name AleSpriteRepository
extends RefCounted

const TextureLoaderScript := preload("res://scripts/content/runtime_texture_loader.gd")
const DEFAULT_INDEX_PATH := "res://data/content/glory_sprite_runtime_index_v1.json"
const DEFAULT_PALETTE_INDEX_PATH := "res://data/content/glory_monster_palette_runtime_index_v1.json"

var content_version := ""
var errors: PackedStringArray = []
var _by_logical_id: Dictionary = {}
var _logical_ids_by_basename: Dictionary = {}
var _metadata_cache: Dictionary = {}
var _page_cache: Dictionary = {}


## 加载 ALE 逻辑路径索引；图片和帧描述仍保持按需读取。
func load_default() -> bool:
	if not load_file(DEFAULT_INDEX_PATH):
		return false
	return merge_file(DEFAULT_PALETTE_INDEX_PATH)


func load_file(path: String) -> bool:
	errors.clear()
	_by_logical_id.clear()
	_logical_ids_by_basename.clear()
	_metadata_cache.clear()
	_page_cache.clear()
	return _merge_file(path)


func merge_file(path: String) -> bool:
	errors.clear()
	return _merge_file(path)


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
		if logical_id.is_empty() or not frames_path.begins_with("res://content/glory/"):
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
static func normalize_reference(reference: String) -> String:
	var normalized := reference.strip_edges().replace("\\", "/").to_lower()
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
func resolve(reference: String, preferred_prefix := "") -> Dictionary:
	var normalized := normalize_reference(reference)
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


func size() -> int:
	return _by_logical_id.size()


## 返回帧描述、页贴图和原点，可直接供 AnimatedSprite2D 表现适配器消费。
func load_animation(reference: String, preferred_prefix := "") -> Dictionary:
	var definition := resolve(reference, preferred_prefix)
	if definition.is_empty():
		return {}
	var logical_id := String(definition["logical_id"])
	var metadata: Dictionary = _metadata_cache.get(logical_id, {})
	if metadata.is_empty():
		var frames_path := String(definition["frames_path"])
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(frames_path))
		if not parsed is Dictionary:
			return {}
		metadata = parsed
		_metadata_cache[logical_id] = metadata
	var page_textures: Array[Texture2D] = []
	for page_path_value: Variant in definition.get("page_paths", []):
		var page_path := String(page_path_value)
		var texture: Texture2D = _page_cache.get(page_path)
		if texture == null:
			texture = TextureLoaderScript.load_texture(page_path)
			if texture == null:
				return {}
			_page_cache[page_path] = texture
		page_textures.append(texture)
	var frames: Array[Dictionary] = []
	for frame_value: Variant in metadata.get("frames", []):
		if not frame_value is Dictionary:
			return {}
		var frame: Dictionary = frame_value
		var page_index := int(frame.get("page", -1))
		if page_index < 0 or page_index >= page_textures.size():
			return {}
		var atlas := AtlasTexture.new()
		atlas.atlas = page_textures[page_index]
		atlas.region = Rect2(
			float(frame.get("x", 0)),
			float(frame.get("y", 0)),
			float(frame.get("width", 0)),
			float(frame.get("height", 0)),
		)
		frames.append({
			"index": int(frame.get("index", frames.size())),
			"texture": atlas,
			"origin": Vector2(float(frame.get("origin_x", 0)), float(frame.get("origin_y", 0))),
			"size": atlas.region.size,
		})
	return {
		"logical_id": logical_id,
		"frames": frames,
		"cell_size": Vector2(
			float(metadata.get("cell_width", 0)), float(metadata.get("cell_height", 0))
		),
		"source_release": "starhome_lz_ry",
	}


func _add_error(field: String, message: String) -> void:
	errors.append("%s: %s" % [field, message])
