extends SceneTree

var failures := PackedStringArray()


## 验证自由坐标、允许重叠、仅手动整理对齐，以及旧存档元数据兼容。
func _initialize() -> void:
	var items: Array = [
		{"instance_id": "a", "position_px": [17, 43], "footprint_px": [500, 500]},
		{"instance_id": "b", "position_px": [17, 43]},
	]
	_expect(InventoryLayout.validate(items).is_ok, "允许完全重叠，尺寸不参与占位判定")
	var moved := InventoryLayout.move_item(items, "a", Vector2i(92, 61))
	_expect(moved.is_ok and moved.value[0].position_px == [92, 61], "移动不吸附网格")
	_expect(items[0].position_px == [17, 43], "移动不能修改输入数组")
	var overlap := InventoryLayout.move_item(moved.value, "a", Vector2i(17, 43))
	_expect(overlap.is_ok and overlap.value[0].position_px == overlap.value[1].position_px,
		"移动到已占用坐标应成功，不移动另一件物品")
	var arranged := InventoryLayout.arrange(items)
	_expect(arranged.is_ok and arranged.value[0].position_px == [0, 0] \
		and arranged.value[1].position_px == [55, 0], "手动整理才按五列网格对齐")
	_expect(InventoryLayout.first_available_position(arranged.value, Vector2i(500, 500)) \
		== Vector2i(110, 0), "新入包落位按统一图标推荐位置，不受旧占位尺寸限制")
	_expect(not InventoryLayout.move_item(items, "a", Vector2i(276, 0)).is_ok,
		"坐标不能越出背包边界")
	items[0]["locked"] = true
	_expect(not InventoryLayout.move_item(items, "a", Vector2i(92, 61)).is_ok, "锁定校验保留")
	var full: Array = []
	for index: int in 40:
		full.append({"instance_id": "%02d" % index, "position_px": [0, 0]})
	_expect(InventoryLayout.validate(full).is_ok, "四十件物品可以叠在同一个位置")
	var aligned := InventoryLayout.arrange(full)
	_expect(aligned.is_ok and aligned.value[39].position_px == [220, 258],
		"第四十件整理到第五列第八行")
	_expect(InventoryLayout.validate(aligned.value).is_ok, "整理后的所有坐标合法")
	_expect(InventoryLayout.first_available_position(full, Vector2i.ONE) == Vector2i(-1, -1),
		"四十件容量上限不变")
	full.append({"instance_id": "overflow", "position_px": [0, 0]})
	_expect(not InventoryLayout.validate(full).is_ok, "允许重叠不意味着允许超过容量")
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("INVENTORY_FREE_LAYOUT_OK")
	quit(0 if failures.is_empty() else 1)


## 记录布局规则断言。
## [param condition] 必须成立的条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
