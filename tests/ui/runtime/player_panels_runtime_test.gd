extends SceneTree

const ManagerScript := preload("res://scripts/client/ui/windows/game_window_manager.gd")
const ItemHoverHighlightScript := preload(
	"res://scripts/client/ui/windows/item_hover_highlight.gd"
)

var failures: PackedStringArray = []
var assertions := 0


## 延迟运行人物、背包和战车面板运行时测试。
func _initialize() -> void:
	call_deferred("_run")


## 实例化显式离线权威，验证窗口布局、拖动命令和换装快照联动。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var manager = ManagerScript.new()
	root.add_child(manager)
	_expect(manager.configure(Callable(), true), "离线三面板管理器应初始化")
	await process_frame
	_expect(not manager.character_panel.visible, "人物面板初始应隐藏")
	_expect(not manager.inventory_panel.visible, "背包面板初始应隐藏")
	_expect(not manager.vehicle_panel.visible, "战车面板初始应隐藏")
	_expect(manager.toggle("character") and manager.character_panel.visible, "人物按钮应切换单例窗口")
	_expect(manager.toggle("inventory") and manager.inventory_panel.visible, "背包按钮应切换单例窗口")
	_expect(manager.toggle("vehicle_equipment") and manager.vehicle_panel.visible, "战车按钮应切换单例窗口")
	await process_frame
	_expect(manager.character_panel.size == Vector2(355, 450), "人物面板应保持荣耀版原始尺寸")
	_expect(manager.inventory_panel.size == Vector2(338, 469), "背包面板应保持荣耀版原始尺寸")
	_expect(manager.vehicle_panel.size == Vector2(604, 460), "战车面板应保持荣耀版原始尺寸")
	_expect(manager.inventory_panel._item_canvas.get_child_count() == 2, "背包应呈现两个权威物品实例")
	_expect(manager.vehicle_panel._slot_root.get_child_count() == 3, "战车应呈现三个已装备槽位")
	_expect(manager.vehicle_panel._slot_label_root.get_child_count() == 14,
		"战车面板应恢复十四条原版固定槽位文字")
	_expect(manager.vehicle_panel._slot_label_root.get_node("DisplaySlot_6").text == "推进器",
		"视觉槽 6 应沿用原版推进器文字而不是装置编号")
	var slot_zero := manager.vehicle_panel._slot_label_root.get_node("DisplaySlot_0") as Label
	var slot_one := manager.vehicle_panel._slot_label_root.get_node("DisplaySlot_1") as Label
	_expect(slot_zero.position == Vector2(30, 122) and slot_one.position == Vector2(101, 122),
		"ButtonText 源码坐标应作为文字左上角直接使用")
	_expect(slot_zero.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT \
		and slot_zero.get_theme_font_size("font_size") == 12,
		"槽位文字应为左对齐宋体 12px")
	_expect((slot_zero.get_theme_font("font") as SystemFont).font_weight == 400 \
		and not slot_zero.has_theme_constant_override("shadow_offset_x"),
		"槽位文字应使用常规字重且不添加源码不存在的阴影")
	slot_zero.mouse_entered.emit()
	_expect(slot_zero.get_theme_color("font_color") == Color("f6f3e8"),
		"装置0 等普通文字悬停后仍应保持白色")
	slot_one.mouse_entered.emit()
	_expect(slot_one.get_theme_color("font_color") == Color("ffcc00"),
		"只有装置1 应复现源码中的黄色悬停差异")
	slot_one.mouse_exited.emit()
	_expect(manager.current_player.is_ready(), "窗口管理器应维护当前登录人物的同版本全局投影")
	_expect(manager.character_panel._portrait_body.position == Vector2(56, 64),
		"男性裸体底模应包含人物预览子窗口偏移")
	_expect(manager.character_panel._skill_button.text == "查看技能", "人物资料区应提供查看技能入口")
	_expect(manager.character_panel._skill_rows_root.get_child_count() == 13,
		"技能弹层应呈现十三项权威技能")
	var inventory_item := manager.inventory_panel._item_canvas.get_child(0) as InventoryItemView
	var inventory_icon := inventory_item.get_node("Icon") as TextureRect
	inventory_item.mouse_entered.emit()
	_expect(_is_item_highlighted(inventory_icon), "背包物品悬停应启用原版绿色发光")
	var legacy_tooltip := ItemHoverHighlightScript.active_tooltip()
	_expect(legacy_tooltip != null and legacy_tooltip.visible,
		"物品复杂说明应在 mouse_entered 当次立即显示")
	var tooltip_title := legacy_tooltip.get_node("Content/Title") as Label
	var tooltip_body := legacy_tooltip.get_node("Content/Body") as Label
	_expect(tooltip_title.get_theme_font_size("font_size") == 12 \
		and tooltip_body.get_theme_font_size("font_size") == 12,
		"物品说明标题和正文应使用原版宋体 12px 高度")
	_expect((tooltip_title.get_theme_font("font") as SystemFont).font_weight == 800,
		"物品说明标题应使用 SETFONT2 对应的粗体字重")
	_expect(is_equal_approx(inventory_item.modulate.a, 1.0),
		"悬停材质不得覆盖背包拖拽透明度状态")
	inventory_item.mouse_exited.emit()
	_expect(not _is_item_highlighted(inventory_icon), "背包物品离开后应清除发光")
	_expect(legacy_tooltip.visible, "离开物品后应保留短暂时间供鼠标进入说明窗")
	await create_timer(0.12).timeout
	_expect(not legacy_tooltip.visible, "鼠标未进入说明窗时应在 100ms 检查后隐藏")
	manager.inventory_panel._request_character_equip("inventory.training_shirt", "upper_body")
	await process_frame
	var shirt := manager.character_panel._equipment_layers.get_child(0) as TextureRect
	_expect(shirt.position == Vector2(54, 93), "衣服应按 WearInDlg 锚点与 ALE origin 叠加")
	shirt.mouse_entered.emit()
	_expect(_is_item_highlighted(shirt), "人物面板穿着物品应使用同一绿色发光")
	legacy_tooltip = ItemHoverHighlightScript.active_tooltip()
	tooltip_body = legacy_tooltip.get_node("Content/Body") as Label
	_expect("服装等级：35" in tooltip_body.text and "耐久：64 / 64" in tooltip_body.text,
		"悬浮衣服应在原版式复杂说明窗显示等级和耐久")
	_expect(shirt.tooltip_text.is_empty(), "人物物品不得再触发 Godot 延迟 tooltip")
	shirt.mouse_exited.emit()
	var chassis_visual := manager.vehicle_panel._slot_root.get_node("Location_0_recruit_tank") as TextureRect
	var weapon_visual := manager.vehicle_panel._slot_root.get_node("Location_1_recruit_energy_cannon") as TextureRect
	var engine_visual := manager.vehicle_panel._slot_root.get_node("Location_3_beginner_engine") as TextureRect
	_expect(chassis_visual.position == Vector2(93, 208), "底盘应使用旧客户端对话框坐标")
	_expect(weapon_visual.position == Vector2(138, 184), "主武器应叠在底盘对应锚点")
	_expect(engine_visual.position == Vector2(97, 370), "推进器应落在原版底部装备槽")
	weapon_visual.mouse_entered.emit()
	_expect(_is_item_highlighted(weapon_visual), "战车装备应使用同一物品悬停发光")
	weapon_visual.mouse_exited.emit()
	_expect(manager.vehicle_panel._stat_labels.max_health.text == "最大生命：70",
		"右侧最大生命应消费权威聚合值")
	_expect(manager.vehicle_panel._stat_labels.armor_values.text == "0 / 0 / 0 / 0",
		"右侧四向护甲应按独立槽位显示")
	_expect(manager.vehicle_panel._stat_labels.output_power.text == "输出功率：21.0",
		"输出功率应保持旧客户端一位小数语义")
	manager.inventory_panel._request_move("inventory.spare_engine", Vector2i(92, 61))
	await process_frame
	var moved_found := false
	for item in manager.inventory_panel._item_canvas.get_children():
		if String(item.item_snapshot.get("instance_id", "")) == "inventory.spare_engine":
			moved_found = item.position == Vector2(90, 60)
	_expect(moved_found, "权威回包应将拖动位置吸附到 15 像素网格")
	manager.character_panel.position = Vector2(5000, 5000)
	manager.character_panel.clamp_to_viewport(Vector2(1280, 720))
	_expect(manager.character_panel.position == Vector2(925, 270), "拖动窗口必须限制在当前视口")
	_test_right_click_close(manager)
	_finish(manager)


## 验证右键只关闭命中位置的最上层面板，并覆盖物品子控件区域。
## [param manager] 本次运行时测试创建的窗口管理器。
func _test_right_click_close(manager: Control) -> void:
	manager.character_panel.position = Vector2(100, 100)
	manager.inventory_panel.position = Vector2(100, 100)
	manager.character_panel.visible = true
	manager.inventory_panel.visible = true
	manager.inventory_panel.move_to_front()
	manager._input(_right_click(Vector2(150, 150)))
	_expect(not manager.inventory_panel.visible and manager.character_panel.visible,
		"重叠窗口右键应只关闭绘制顺序最上层的一扇")

	manager.inventory_panel.visible = true
	manager.inventory_panel.move_to_front()
	var first_item := manager.inventory_panel._item_canvas.get_child(0) as Control
	manager._input(_right_click(first_item.get_global_rect().get_center()))
	_expect(not manager.inventory_panel.visible,
		"右键命中背包物品子控件时也应关闭所属面板")

	manager.vehicle_panel.visible = true
	manager._input(_right_click(Vector2(1275, 715)))
	_expect(manager.vehicle_panel.visible, "面板外右键不得关闭任何窗口")


## 创建一次右键按下输入。
## [param viewport_position] 右键事件在视口内的位置。
## 返回已设置为按下状态的鼠标右键事件。
func _right_click(viewport_position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = viewport_position
	return event


## 汇总测试结果并释放窗口管理器。
## [param manager] 本次测试创建的窗口管理器。
func _finish(manager: Control) -> void:
	if failures.is_empty():
		print("PLAYER_PANELS_RUNTIME_OK (%d assertions)" % assertions)
		manager.free()
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	manager.free()
	quit(1)


## 记录一个运行时布尔断言。
## [param condition] 预期成立的条件。
## [param message] 失败信息。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 判断物品专属材质当前是否处于悬停状态。
## [param visual] 待检查材质参数的物品表现节点。
## 返回悬停强度为 1 时为 true。
func _is_item_highlighted(visual: CanvasItem) -> bool:
	var material := visual.material as ShaderMaterial
	return material != null \
		and is_equal_approx(float(material.get_shader_parameter("hover_amount")), 1.0)
