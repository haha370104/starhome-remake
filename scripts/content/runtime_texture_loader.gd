class_name RuntimeTextureLoader
extends RefCounted


## 兼容 Godot 已导入贴图与运行时内容包中的原始 PNG/JPEG。
## [param path] 调用方传入的 `path` 参数。
## 返回该函数计算、查询或操作得到的结果。
static func load_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	if ResourceLoader.exists(path):
		var imported := ResourceLoader.load(path)
		if imported is Texture2D:
			return imported
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
	return ImageTexture.create_from_image(image)
