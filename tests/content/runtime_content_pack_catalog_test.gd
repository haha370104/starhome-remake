extends SceneTree

const CatalogScript := preload("res://scripts/content/runtime_content_pack_catalog.gd")
const TextureLoaderScript := preload("res://scripts/content/runtime_texture_loader.gd")

var failures: PackedStringArray = []
var assertions := 0


func _initialize() -> void:
	var catalog = CatalogScript.new()
	_expect(catalog.load_file("res://tests/content/fixtures/content_pack_catalog.json"), "; ".join(catalog.errors))
	_expect(catalog.content_version == "test-content-v1", "应保留内容版本")
	_expect(catalog.pack_ids() == [&"test_mount_pack"], "应读取唯一测试内容包")
	_expect(catalog.mount_all(true), "; ".join(catalog.errors))
	_expect(catalog.is_mounted(&"test_mount_pack"), "挂载状态应可查询")
	var mounted_path := "res://content/test/mounted_payload.txt"
	_expect(FileAccess.file_exists(mounted_path), "挂载后应暴露包内 res:// 文件")
	_expect(
		FileAccess.get_file_as_string(mounted_path).strip_edges() == "荣耀版内容包挂载测试",
		"包内文本内容不匹配",
	)
	_expect(catalog.mount_pack(&"test_mount_pack", true), "重复挂载应幂等")
	var texture: Texture2D = TextureLoaderScript.load_texture("res://content/test/raw_texture.png")
	_expect(texture != null, "应能从内容包解码未经 Godot 导入的 PNG")
	if texture != null:
		_expect(texture.get_size() == Vector2(2, 2), "包内 PNG 尺寸不匹配")
	if failures.is_empty():
		print("RUNTIME_CONTENT_PACK_CATALOG_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
