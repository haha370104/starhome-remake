extends SceneTree

var failures := PackedStringArray()
var assertions := 0


## 验证旧平铺配置与新三模式配置都不会跨场景误选素材。
func _initialize() -> void:
	var legacy := GameItem.new({"presentation": {
		"icon": "bag.png", "native_size": [40, 21],
		"dialog_texture": "dialog.png", "dialog_origin": [-32, -16],
		"dialog_anchor": [170, 200], "z_layer": 20,
	}})
	var dialog := legacy.presentation_for("dialog")
	_expect(dialog.get("dialog_texture") == "dialog.png", "旧对话框应保留大图")
	_expect(not dialog.has("icon") and not dialog.has("native_size"),
		"背包图片和尺寸不得泄漏到对话框模式")
	_expect(dialog.get("dialog_origin") == [-32, -16] and dialog.get("z_layer") == 20,
		"模式隔离必须保留叠图原点和层级")
	var inventory := legacy.presentation_for("inventory")
	_expect(inventory.get("icon") == "bag.png" and not inventory.has("dialog_texture"),
		"背包只应使用小图")
	_expect(legacy.visual_size_for("inventory") == Vector2i(40, 21), "背包原生尺寸不变")
	dialog["dialog_origin"][0] = 100
	_expect(legacy.presentation_for("dialog")["dialog_origin"] == [-32, -16],
		"调用方不能通过表现副本改变领域物品")
	var structured := GameItem.new({"presentation": {
		"inventory": {"ale_reference": "bag.ale"},
		"dialog": {"ale_reference": "dlg.ale"},
		"world": {"ale_reference": "body.ale"},
	}})
	for mode: String in ["inventory", "dialog", "world"]:
		_expect(structured.presentation_for(mode).size() == 1,
			"结构化 %s 模式只能取得自己的素材" % mode)
	var bag_only := GameItem.new({"presentation": {"inventory": {"icon": "bag.png"}}})
	_expect(bag_only.presentation_for("dialog").is_empty(), "缺失模式不能回退成整份配置")
	var legacy_bag := GameItem.new({"presentation": {"icon": "bag.png"}})
	_expect(legacy_bag.presentation_for("dialog").is_empty(), "缺失大图不能用背包图冒充")
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
