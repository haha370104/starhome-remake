extends SceneTree

const CatalogScript := preload("res://scripts/maps/map_catalog.gd")
const LoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const NavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")

var assertions := 0
var failures: Array[String] = []


## 验证首张批量提升地图的表现、导航和双向图谱已进入真实运行目录。
func _initialize() -> void:
	var catalog := CatalogScript.new()
	var directory: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/maps/map_directory.json")
	)
	var paths := PackedStringArray()
	for path_value: Variant in (directory.get("definitions", {}) as Dictionary).values():
		paths.append(String(path_value))
	_expect(catalog.add_files(paths), "运行地图目录应完整加载：%s" % catalog.errors)
	_expect(catalog.validate_links(), "运行地图内部传送应完整解析：%s" % catalog.errors)

	var c03: MapDefinition = catalog.map_by_id(&"buli_c03_field_zone")
	var c04: MapDefinition = catalog.map_by_id(&"buli_c04_field_zone")
	var d03: MapDefinition = catalog.map_by_id(&"buli_d03_field_zone")
	var d04: MapDefinition = catalog.map_by_id(&"d04_field_zone")
	_expect(c03 != null, "NFT_BL/C03 应成为可运行地图")
	_expect(c04 != null, "NFT_BL/C04 应成为可运行地图")
	_expect(d03 != null, "NFT_BL/D03 应成为可运行地图")
	_expect(d04 != null, "D04 运行地图应继续存在")
	if c03 != null:
		_expect(c03.world_id == &"buli", "C03 应保留布里世界身份")
		_expect(c03.source_audit.get("presentation_state") == "runtime_ready", "C03 表现应提升完成")
		_expect(c03.source_audit.get("scene_objects_missing") == 0, "C03 不应遗漏已解析场景物件")
		var navigation := NavigationScript.new()
		_expect(
			navigation.load_from(
				c03.navigation_data_path,
				c03.navigation_grid_size,
				c03.navigation_cell_size,
			),
			"C03 应加载原版导航网格",
		)
		_expect(navigation.is_walkable(Vector2(4678, 4574)), "D04 到 C03 的落点应可行走")
		_expect(
			catalog.resolve_target(c03.transition_by_id(&"exit_to_d04_field"), c03.world_id) == d04,
			"C03 返回 D04 的内部边应解析",
		)
		_expect(
			catalog.resolve_target(c03.transition_by_id(&"exit_to_c04_field"), c03.world_id) == c04,
			"C03 到 C04 的内部边应解析",
		)
		_expect(
			catalog.resolve_target(c03.transition_by_id(&"exit_to_d03_field"), c03.world_id) == d03,
			"C03 到 D03 的内部边应解析",
		)
	for imported: MapDefinition in [c04, d03]:
		if imported == null:
			continue
		_expect(imported.world_id == &"buli", "新增地图应保留布里世界身份")
		_expect(
			imported.source_audit.get("scene_objects_missing") == 0,
			"新增地图不应遗漏已解析场景物件",
		)
	if d04 != null:
		_expect(
			catalog.resolve_target(d04.transition_by_id(&"exit_to_c03_field"), d04.world_id) == c03,
			"D04 左上出口应解析到布里 C03",
		)
	_finish()


## 记录一项测试断言及其失败信息。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 汇总测试断言并以对应退出码结束测试。
func _finish() -> void:
	if failures.is_empty():
		print("BULI_C03_RUNTIME_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
