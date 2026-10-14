class_name ItemPresentationTextureResolver
extends RefCounted

const RepositoryScript := preload("res://scripts/content/ale_sprite_repository.gd")
const RuntimeContentBootstrapScript := preload("res://scripts/content/runtime_content_bootstrap.gd")

static var _repository: RefCounted
static var _initialized := false


## 将业务表现定义解析为贴图、ALE 原点和原生尺寸；旧 PNG 路径仍原样兼容。
## [param presentation] 调用方传入的 `presentation` 参数。
## 返回该函数计算、查询或操作得到的结果。
static func resolve(presentation: Dictionary) -> Dictionary:
	var texture_path := String(presentation.get(
		"icon", presentation.get("dialog_texture", presentation.get("texture", ""))
	))
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		var texture := ResourceLoader.load(texture_path, "Texture2D") as Texture2D
		if texture != null:
			return _apply_source_rect({"texture": texture, "origin": Vector2.ZERO, "size": texture.get_size()}, presentation)
	var ale_reference := String(presentation.get("ale_reference", "")).strip_edges()
	if ale_reference.is_empty() or not _ensure_repository():
		return {}
	var animation: Dictionary = _repository.load_animation(ale_reference)
	var frames: Array = animation.get("frames", [])
	if frames.is_empty():
		return {}
	var frame_index := clampi(int(presentation.get("frame", 0)), 0, frames.size() - 1)
	var frame: Dictionary = frames[frame_index]
	return _apply_source_rect({
		"texture": frame["texture"],
		"origin": frame["origin"],
		"size": frame["size"],
		"logical_id": animation.get("logical_id", ""),
	}, presentation)


## 按离线核对的有效区域裁去帧内透明留白，不修改共享原图或世界表现。
## [param visual] 已解析的独立纹理或图集帧。[param presentation] 可选 source_rect 为帧内 x、y、宽、高。
## 返回裁切后的贴图、修正原点及尺寸；区域无效时拒绝展示。
## 设计：只使用显式配置，不逐帧读回 GPU 图片扫描透明度，也不对所有装备自动裁切。
static func _apply_source_rect(visual: Dictionary, presentation: Dictionary) -> Dictionary:
	if not presentation.has("source_rect"): return visual
	var values: Variant = presentation.source_rect
	if not values is Array or values.size() != 4: return {}
	for value: Variant in values:
		if not (value is int or value is float) or not is_finite(float(value)) \
			or value < 0 or value != floor(value): return {}
	var region := Rect2(values[0], values[1], values[2], values[3])
	var texture := visual.texture as Texture2D
	if not region.has_area() or not Rect2(Vector2.ZERO, texture.get_size()).encloses(region): return {}
	var cropped := AtlasTexture.new()
	cropped.atlas = texture.atlas if texture is AtlasTexture else texture
	cropped.region = Rect2(texture.region.position + region.position, region.size) if texture is AtlasTexture else region
	cropped.filter_clip = true
	return visual.merged({"texture": cropped, "origin": visual.origin + region.position, "size": region.size}, true)


## 执行 `ensure_repository` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
static func _ensure_repository() -> bool:
	if _initialized:
		return _repository != null
	_initialized = true
	if not bool(RuntimeContentBootstrapScript.mount_default().get("ok", false)):
		return false
	var repository = RepositoryScript.new()
	if not repository.load_default():
		return false
	_repository = repository
	return true
