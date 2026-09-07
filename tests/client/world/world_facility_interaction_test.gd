extends SceneTree

const FacilityScript := preload("res://scripts/client/world/world_facility_interaction.gd")
const CATALOG_PATH := "res://data/world/manufacturing_facilities_v1.json"

var failures := PackedStringArray()
var assertions := 0


## 验证生产设施目录、命中半径与统一 NPC 交互协议。
func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	_expect(parsed is Dictionary, "生产设施目录应为有效 JSON 对象")
	if not parsed is Dictionary:
		_finish()
		return
	var maps: Dictionary = parsed.get("maps", {})
	_expect((maps.get("glory_nft_bl_clothshop1", []) as Array).size() == 4, "服装店应恢复四台裁缝机")
	_expect((maps.get("glory_nft_bl_foodroom1", []) as Array).size() == 2, "食品店应登记两处烹饪交互锚点")
	_expect((maps.get("glory_nft_bl_factory1", []) as Array).size() == 5, "提炼厂一层应登记五处原图设备")
	_expect((maps.get("glory_nft_bl_armshop1", []) as Array).size() == 4, "兵工厂应有四类制造设施")
	for map_id: String in ["dragon_city_refinery_floor_2", "dragon_city_refinery_floor_3"]:
		_expect(not (maps.get(map_id, []) as Array).is_empty(), "提炼厂分层均应有可点击设施")
	var facility: Node2D = FacilityScript.new()
	root.add_child(facility)
	var configured: Error = facility.configure({
		"facility_id": "test_tailor",
		"station_id": "tailoring",
		"name": "裁缝机",
		"position": [100, 200],
		"interaction_radius": 52,
	})
	_expect(configured == OK, "有效设施定义应可完成配置")
	_expect(facility.hit_test(Vector2(140, 200)), "设施应接受配置半径内的点击")
	_expect(not facility.hit_test(Vector2(153, 200)), "设施应拒绝配置半径外的点击")
	var interaction: Dictionary = facility.get_interaction_data()
	_expect(String(interaction.get("title", "")) == "裁缝机", "设施应使用地图业务名称")
	_expect(String((interaction.get("actions", []) as Array)[0].get("id", "")) == "manufacture", "设施应暴露统一制造动作")
	facility.free()
	_finish()


## 记录一条测试断言。
## [param condition] 条件是否成立。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出测试结果并结束进程。
func _finish() -> void:
	if failures.is_empty():
		print("WORLD_FACILITY_INTERACTION_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
