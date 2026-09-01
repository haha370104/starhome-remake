extends SceneTree

const PackCatalogScript := preload("res://scripts/content/runtime_content_pack_catalog.gd")
const MapCatalogScript := preload("res://scripts/maps/map_catalog.gd")
const TextureLoaderScript := preload("res://scripts/content/runtime_texture_loader.gd")
const PACK_CATALOG_PATH := "res://data/content/glory_map_content_packs_v1.json"
const MAP_DIRECTORY_PATH := "res://data/maps/glory_map_directory_v1.json"

var failures: PackedStringArray = []
var assertions := 0


## 执行本测试脚本的全部验证并汇总结果。
func _initialize() -> void:
	var packs = PackCatalogScript.new()
	_expect(packs.load_file(PACK_CATALOG_PATH), "; ".join(packs.errors))
	_expect(packs.pack_ids().size() == 11, "全量地图应拆为一个索引包和十个表现包")
	_expect(packs.mount_all(false), "; ".join(packs.errors))
	var directory: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_DIRECTORY_PATH))
	_expect(directory is Dictionary, "全量地图目录必须是 JSON object")
	if not directory is Dictionary:
		_finish()
		return
	var definitions: Dictionary = directory.get("definitions", {})
	_expect(definitions.size() == 810, "应注册 810 个有完整实物的荣耀版地图键")
	var definition_paths := PackedStringArray()
	for map_id: String in definitions:
		var definition_path := String(definitions[map_id])
		_expect(FileAccess.file_exists(definition_path), "地图定义缺失：%s" % map_id)
		definition_paths.append(definition_path)
	var maps = MapCatalogScript.new()
	_expect(maps.add_files(definition_paths), "地图定义校验失败：%s" % "; ".join(maps.errors))
	_expect(maps.size() == 810, "领域地图目录数量不匹配")
	_expect(maps.validate_links(), "地图内部出口关系无法闭合：%s" % "; ".join(maps.errors))
	_test_buli_recovered_field_transitions(maps)
	var generated = maps.map_by_id(&"glory_nft_bl_2armshop1")
	_expect(generated != null, "应能查询自动生成的兵工厂地图")
	if generated != null:
		for key in ["floor", "minimap", "scene_manifest"]:
			_expect(
				FileAccess.file_exists(String(generated.resource_paths.get(key, ""))),
				"兵工厂表现资源缺失：%s" % key,
			)
		_expect(FileAccess.file_exists(generated.navigation_data_path), "兵工厂导航资源缺失")
		var floor := TextureLoaderScript.load_texture(String(generated.resource_paths["floor"]))
		_expect(floor != null and floor.get_size() == generated.world_size, "包内地图底图应可解码")
	_finish()


## 验证荣耀版柏雷分支中缺失的出口表均由同包兄弟分支恢复。
## [param maps] 已加载全量定义的地图目录。
func _test_buli_recovered_field_transitions(maps) -> void:
	var recovered_codes := PackedStringArray([
		"c05", "c06", "e03", "e08", "f03", "f08", "h05", "h06",
	])
	for code in recovered_codes:
		var definition: MapDefinition = maps.map_by_legacy_code(code, &"buli")
		_expect(definition != null, "柏雷恢复地图缺失：%s" % code.to_upper())
		if definition == null:
			continue
		_expect(
			definition.enabled_transitions().size() == 5,
			"柏雷 %s 应恢复五个荣耀版出口" % code.to_upper(),
		)
		_expect(
			definition.source_audit.get("transition_recovery") is Dictionary,
			"柏雷 %s 必须保留出口恢复证据" % code.to_upper(),
		)
	var c05: MapDefinition = maps.map_by_legacy_code("c05", &"buli")
	if c05 == null:
		return
	var targets := PackedStringArray()
	for transition: MapTransition in c05.enabled_transitions():
		targets.append(transition.destination_legacy_code)
	targets.sort()
	_expect(
		Array(targets) == ["c04", "c06", "d04", "d05", "d06"],
		"C05 恢复出口集合不完整：%s" % ", ".join(targets),
	)


## 汇总测试断言并以对应退出码结束测试。
func _finish() -> void:
	if failures.is_empty():
		print("GLORY_FULL_MAP_PACK_OK (%d assertions)" % assertions)
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
