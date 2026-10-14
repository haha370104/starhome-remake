class_name RuntimeTextureLoader
extends RefCounted

static var cache := TextureLruCache.new()


## 兼容 Godot 已导入贴图与运行时内容包中的原始 PNG/JPEG。
## [param path] 调用方传入的 `path` 参数。
## 返回该函数计算、查询或操作得到的结果。
static func load_texture(path: String) -> Texture2D:
	var _timing := PerformanceTelemetry.measure(&"resource_texture_load")
	var cached := cache.fetch(path)
	if cached != null:
		PerformanceTelemetry.increment(&"texture_cache_hit")
		return cached
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	if ResourceLoader.exists(path):
		var imported := ResourceLoader.load(path)
		if imported is Texture2D:
			cache.retain(path, imported)
			return imported
	var decoded := decode_image(path)
	if decoded == null: return null
	var texture := ImageTexture.create_from_image(decoded)
	cache.retain(path, texture)
	return texture


## 只读文件并解码独立 Image，可在工作线程执行，不触碰节点或 GPU。
## [param path] 已挂载内容包或本地 PNG/JPEG/WebP 路径。
## 返回独立图像，失败返回 null。
static func decode_image(path: String) -> Image:
	var _timing := PerformanceTelemetry.measure(&"resource_image_decode")
	if not FileAccess.file_exists(path): return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	var extension := path.get_extension().to_lower()
	var error := ERR_FILE_UNRECOGNIZED
	if extension == "png":
		error = image.load_png_from_buffer(bytes)
	elif extension in ["jpg", "jpeg"]:
		error = image.load_jpg_from_buffer(bytes)
	elif extension == "webp":
		error = image.load_webp_from_buffer(bytes)
	if error != OK or image.is_empty():
		return null
	return image
