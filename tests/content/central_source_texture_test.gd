extends SceneTree


## 在 Godot 中核对中枢导入图标能按清单加载并保持原始尺寸。
func _initialize() -> void:
	call_deferred("_run")


## 逐项加载中枢清单中的纹理并报告失败。
func _run() -> void:
	var manifest_path := "res://assets/items/central/manifest.json"
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary:
		push_error("中枢素材清单无法读取")
		quit(1)
		return
	var frames: Array = manifest.get("frames", [])
	var failures := 0
	for frame: Dictionary in frames:
		var path := "res://assets/items/central/" + String(frame.file)
		var texture := RuntimeTextureLoader.load_texture(path)
		if texture == null or texture.get_size() != Vector2(frame.native_size[0], frame.native_size[1]):
			push_error("中枢纹理无法按原始尺寸加载：" + path)
			failures += 1
	if frames.size() != 69:
		push_error("中枢清单应有 69 个来源帧")
		failures += 1
	print("CENTRAL_SOURCE_TEXTURES checked=%d failures=%d" % [frames.size(), failures])
	quit(0 if failures == 0 else 1)
