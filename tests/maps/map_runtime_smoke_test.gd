extends SceneTree

const LoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const CatalogScript := preload("res://scripts/maps/map_catalog.gd")

var failures: PackedStringArray = []


## 运行地图定义加载、目录校验和业务适配的全部冒烟用例并汇总结果。
## Design: 该入口组合多个独立 JSON 夹具，以进程退出码表达测试结果。
func _initialize() -> void:
	_test_valid_configuration()
	_test_bad_coordinate()
	_test_duplicate_id()
	_test_empty_transitions()
	_test_unresolved_external_target()
	_test_unresolved_internal_target()
	_test_business_adapter_configuration()
	if failures.is_empty():
		print("MAP_RUNTIME_SMOKE_OK (7 cases)")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 验证合法野外地图配置能完整保留业务标识、出口和来源审计信息。
func _test_valid_configuration() -> void:
	var loader := LoaderScript.new()
	var definition = loader.load_file("res://tests/maps/fixtures/valid_field_map.json")
	_expect(definition != null, "合法地图配置应加载成功：%s" % loader.errors)
	if definition == null:
		return
	_expect(definition.map_id == &"g08_field_zone", "业务 map_id 未保留")
	_expect(definition.transitions.size() == 2, "合法跳转没有完整加载")
	_expect(definition.transition_by_id(&"west_to_f08").destination_legacy_code == "f08", "旧代码目标未保留")
	_expect(definition.source_audit.get("source_release") == "glory", "荣耀版溯源没有保留")


## 验证超出地图边界的坐标会被加载器拒绝并产生明确错误。
func _test_bad_coordinate() -> void:
	var loader := LoaderScript.new()
	var definition = loader.load_file("res://tests/maps/fixtures/invalid_coordinate.json")
	_expect(definition == null, "超出地图范围的坐标必须被拒绝")
	_expect(_contains(loader.errors, "超出地图范围"), "坏坐标错误信息不明确：%s" % loader.errors)


## 验证地图目录拒绝重复业务 ID 并留下可审计的错误代码。
func _test_duplicate_id() -> void:
	var loader := LoaderScript.new()
	var first = loader.load_file("res://tests/maps/fixtures/valid_empty_map.json")
	var second = loader.load_file("res://tests/maps/fixtures/valid_empty_map.json")
	var catalog := CatalogScript.new()
	_expect(catalog.add_map(first), "首次加入地图目录应成功")
	_expect(not catalog.add_map(second), "重复 map_id 必须被拒绝")
	_expect(_contains(catalog.errors, "duplicate_map_id"), "重复 ID 错误未记录")


## 验证没有出口的地图仍是合法配置且保持空跳转集合。
func _test_empty_transitions() -> void:
	var loader := LoaderScript.new()
	var definition = loader.load_file("res://tests/maps/fixtures/valid_empty_map.json")
	_expect(definition != null, "空出口地图应当合法：%s" % loader.errors)
	if definition != null:
		_expect(definition.transitions.is_empty(), "空出口应保留为空数组")


## 验证外部目标可延迟解析，同时目录查询与来源审计保持有效。
## Design: 外部出口是跨内容包协议边界，允许缺席但必须显式列入审计结果。
func _test_unresolved_external_target() -> void:
	var catalog := CatalogScript.new()
	var loader := LoaderScript.new()
	var source = loader.load_file("res://tests/maps/fixtures/valid_field_map.json")
	var target = loader.load_file("res://tests/maps/fixtures/valid_empty_map.json")
	catalog.add_map(source)
	catalog.add_map(target)
	_expect(catalog.map_by_id(&"g08_field_zone") == source, "按 map_id 查询失败")
	_expect(catalog.map_by_legacy_code("G08") == source, "旧代码查询应忽略大小写")
	_expect(catalog.validate_links(), "显式 external 的未解析目标应当保留且不报错：%s" % catalog.errors)
	_expect(catalog.unresolved_external_transitions().size() == 1, "外部未解析目标应可供审计")
	_expect(catalog.source_audit_for_map(&"g08_field_zone").get("source_release") == "glory", "Catalog 溯源查询失败")


## 验证未声明为外部的缺失内部目标会使目录链接校验失败。
func _test_unresolved_internal_target() -> void:
	var loader := LoaderScript.new()
	var source = loader.load_file("res://tests/maps/fixtures/valid_field_map.json")
	var transition = source.transition_by_id(&"west_to_f08")
	transition.destination_map_id = &"missing_internal_map"
	transition.destination_legacy_code = "missing_internal"
	var catalog := CatalogScript.new()
	catalog.add_map(source)
	_expect(not catalog.validate_links(), "未声明 external 的缺失目标必须报告")
	_expect(_contains(catalog.errors, "unresolved_target"), "未解析目标错误未记录")


## 验证易安港大厅业务适配配置与荣耀版导航及来源元数据一致。
func _test_business_adapter_configuration() -> void:
	var loader := LoaderScript.new()
	var definition = loader.load_file("res://data/maps/yian_harbor_hall_floor_1.json")
	_expect(definition != null, "易安港业务适配配置应加载成功：%s" % loader.errors)
	if definition == null:
		return
	_expect(definition.navigation_grid_size == Vector2i(41, 320), "荣耀版导航网格元数据未加载")
	_expect(
		definition.source_audit.get("migration_state") == "glory_import_complete",
		"大厅素材必须完成荣耀版迁移",
	)
	_expect(
		definition.source_audit.get("source_release") == "starhome_lz_ry",
		"大厅正式来源必须是荣耀版",
	)


## 检查 [param values] 中是否至少有一项包含 [param needle] 子串。
## Returns 找到匹配项时为 true，否则为 false。
func _contains(values: PackedStringArray, needle: String) -> bool:
	for value in values:
		if needle in value:
			return true
	return false


## 在 [param condition] 不成立时将 [param message] 加入失败集合。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
