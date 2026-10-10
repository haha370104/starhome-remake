extends SceneTree

const CatalogScript := preload("res://scripts/content/runtime_content_pack_catalog.gd")
const TextureLoaderScript := preload("res://scripts/content/runtime_texture_loader.gd")

var failures: PackedStringArray = []
var assertions := 0


## 执行本测试脚本的全部验证并汇总结果。
func _initialize() -> void:
	var catalog = CatalogScript.new()
	_expect(catalog.load_file("res://tests/content/fixtures/content_pack_catalog.json"), "; ".join(catalog.errors))
	_expect(catalog.content_version == "test-content-v1", "应保留内容版本")
	_expect(catalog.pack_ids() == [&"test_mount_pack"], "应读取唯一测试内容包")
	_expect(catalog.mount_all(), "; ".join(catalog.errors))
	_expect(catalog.is_mounted(&"test_mount_pack"), "挂载状态应可查询")
	var mounted_path := "res://tests/content/fixtures/mounted_payload.txt"
	_expect(FileAccess.file_exists(mounted_path), "物化内容测试夹具应存在")
	_expect(
		FileAccess.get_file_as_string(mounted_path).strip_edges() == "荣耀版内容包挂载测试",
		"物化内容测试夹具不匹配",
	)
	_expect(catalog.mount_pack(&"test_mount_pack"), "重复挂载应幂等")
	var texture_path := "res://assets/glory/monster_palettes/toxic_gel_standard/idle/sheet.png"
	var texture: Texture2D = TextureLoaderScript.load_texture(texture_path)
	_expect(texture != null, "应能从物化 content 目录解码运行时 PNG")
	if texture != null:
		_expect(texture.get_size().x > 0.0 and texture.get_size().y > 0.0, "运行时 PNG 尺寸必须为正")
	if failures.is_empty():
		print("RUNTIME_CONTENT_PACK_CATALOG_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 记录一项测试断言及其失败信息。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
