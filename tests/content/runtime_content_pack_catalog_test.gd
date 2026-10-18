extends SceneTree

const CatalogScript := preload("res://scripts/content/runtime_content_pack_catalog.gd")
const TextureLoaderScript := preload("res://scripts/content/runtime_texture_loader.gd")

var failures: PackedStringArray = []
var assertions := 0


## 执行本测试脚本的全部验证并汇总结果。
func _initialize() -> void:
	var catalog = CatalogScript.new("user://content_pack_test/")
	_expect(catalog.load_file(_create_fixture()), "; ".join(catalog.errors))
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


## 在隔离测试存档目录生成最小内容包，无需将测试图和 ZIP 保存进素材仓库。
## 返回生成的目录 JSON 路径。
func _create_fixture() -> String:
	var folder := "user://content_pack_test/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder + "fixture.zip"
	var pack := ZIPPacker.new()
	_expect(pack.open(path) == OK, "应创建隔离测试包")
	pack.start_file("content/test/mounted_payload.txt")
	pack.write_file("荣耀版内容包挂载测试".to_utf8_buffer())
	pack.close_file()
	var fixture_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	fixture_image.fill(Color.CYAN)
	pack.start_file("content/test/raw_texture.png")
	pack.write_file(fixture_image.save_png_to_buffer())
	pack.close_file()
	pack.close()
	var entry := {"pack_id": "test_mount_pack", "path": path,
		"size_bytes": FileAccess.get_file_as_bytes(path).size(),
		"sha256": FileAccess.get_sha256(path)}
	var file := FileAccess.open(folder + "catalog.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 1,
		"content_version": "test-content-v1", "packs": [entry]}))
	file.close()
	return folder + "catalog.json"


## 记录一项测试断言及其失败信息。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
