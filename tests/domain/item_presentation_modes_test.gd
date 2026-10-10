extends SceneTree

var failures := PackedStringArray()
var assertions := 0


## 验证表现模式只读取显式声明的当前模式。
func _initialize() -> void:
	var flat := GameItem.new({"presentation": {
		"icon": "bag.png", "native_size": [40, 21],
		"dialog_texture": "dialog.png", "dialog_origin": [-32, -16],
		"dialog_anchor": [170, 200], "z_layer": 20,
	}})
	_expect(flat.presentation_for("inventory").is_empty() and flat.presentation_for("dialog").is_empty(),
		"未声明模式的平铺配置不再作为兼容回退")
	var structured := GameItem.new({"presentation": {
		"inventory": {"icon": "bag.png", "native_size": [40, 21]},
		"dialog": {"dialog_texture": "dialog.png", "dialog_origin": [-32, -16], "z_layer": 20},
		"world": {"texture": "body.png", "native_size": [50, 40]},
	}})
	var inventory := structured.presentation_for("inventory")
	var dialog := structured.presentation_for("dialog")
	_expect(inventory.get("icon") == "bag.png" and inventory.size() == 2, "背包使用显式小图模式")
	_expect(dialog.get("dialog_texture") == "dialog.png" and not dialog.has("icon"), "对话框使用独立大图")
	_expect(structured.visual_size_for("inventory") == Vector2i(40, 21), "背包原生尺寸不变")
	dialog["dialog_origin"][0] = 100
	_expect(structured.presentation_for("dialog")["dialog_origin"] == [-32, -16],
		"调用方不能通过表现副本改变领域物品")
	var bag_only := GameItem.new({"presentation": {"inventory": {"icon": "bag.png"}}})
	_expect(bag_only.presentation_for("dialog").is_empty(), "缺失模式不能回退成整份配置")
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("ITEM_PRESENTATION_MODES_OK (%d assertions)" % assertions)
	quit(0 if failures.is_empty() else 1)


## 记录表现契约断言。
## [param condition] 必须成立的条件。
## [param message] 失败原因。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
