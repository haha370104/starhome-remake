extends SceneTree

const ManagerScript := preload("res://scripts/client/ui/windows/game_window_manager.gd")

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
	_expect(manager.current_player.is_ready(), "窗口管理器应维护当前登录人物的同版本全局投影")
	_expect(manager.character_panel._portrait_body.position == Vector2(56, 64),
		"男性裸体底模应包含人物预览子窗口偏移")
	_expect(manager.character_panel._skill_button.text == "查看技能", "人物资料区应提供查看技能入口")
	_expect(manager.character_panel._skill_rows_root.get_child_count() == 12,
		"技能弹层应呈现十二项权威技能")
	var inventory_item := manager.inventory_panel._item_canvas.get_child(0) as InventoryItemView
	var inventory_icon := inventory_item.get_node("Icon") as TextureRect
	inventory_item.mouse_entered.emit()
	_expect(_is_item_highlighted(inventory_icon), "背包物品悬停应启用原版绿色发光")
	_expect(is_equal_approx(inventory_item.modulate.a, 1.0),
		"悬停材质不得覆盖背包拖拽透明度状态")
	inventory_item.mouse_exited.emit()
	_expect(not _is_item_highlighted(inventory_icon), "背包物品离开后应清除发光")
	manager.inventory_panel._request_character_equip("inventory.training_shirt", "upper_body")
	await process_frame
	var shirt := manager.character_panel._equipment_layers.get_child(0) as TextureRect
	_expect(shirt.position == Vector2(54, 93), "衣服应按 WearInDlg 锚点与 ALE origin 叠加")
	_expect("服装等级：35" in shirt.tooltip_text and "耐久：64 / 64" in shirt.tooltip_text,
		"悬浮衣服应显示逆向所得等级和耐久")
	shirt.mouse_entered.emit()
	_expect(_is_item_highlighted(shirt), "人物面板穿着物品应使用同一绿色发光")
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
	_finish(manager)


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
func _is_item_highlighted(visual: CanvasItem) -> bool:
	var material := visual.material as ShaderMaterial
	return material != null \
		and is_equal_approx(float(material.get_shader_parameter("hover_amount")), 1.0)
