extends SceneTree

const ManagerScript := preload("res://scripts/client/ui/windows/game_window_manager.gd")
const ItemHoverHighlightScript := preload(
	"res://scripts/client/ui/windows/item_hover_highlight.gd"
)
const PanelFixtureScript := preload("res://tests/fixtures/player_panel_service_fixture.gd")

var failures: PackedStringArray = []
var assertions := 0
var panel_fixture


## 延迟运行人物、背包和战车面板运行时测试。
func _initialize() -> void:
	call_deferred("_run")


## 以测试夹具提供权威面板回包，验证窗口布局、拖动命令和换装快照联动。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var manager = ManagerScript.new()
	root.add_child(manager)
	panel_fixture = PanelFixtureScript.new()
	_expect(panel_fixture.initialize().is_ok, "测试面板权威夹具应初始化")
	_expect(manager.configure(PlayerPanelSession.new(Callable(self, "_dispatch_panel_command").bind(manager))),
		"三面板管理器应只依赖统一命令分发器")
	manager.panel_session.dispatch({"type": "query"})
	await process_frame
	for layer: Control in manager.vehicle_panel._slot_root.get_children():
		_expect(layer.z_index == 0, "装备按窗口子树排序，不可越过其他面板")
	_expect(manager.vehicle_panel._special_panel.z_index == 0, "特殊装备也必须留在所属窗口内")
	_expect(not manager.character_panel.visible, "人物面板初始应隐藏")
	_expect(not manager.inventory_panel.visible, "背包面板初始应隐藏")
	_expect(not manager.vehicle_panel.visible, "战车面板初始应隐藏")
	_expect(not manager.skill_panel.visible, "技能面板初始应隐藏")
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
		"槽位文字应为左对齐的共享字体 12px")
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
	_expect(manager.panel_session.current_player.is_ready(), "窗口管理器应维护当前登录人物的同版本全局投影")
	_expect(manager.character_panel._portrait_body.position == Vector2(56, 64),
		"男性裸体底模应包含人物预览子窗口偏移")
	_expect(manager.character_panel._skill_button.text == "查看技能", "人物资料区应提供查看技能入口")
	manager.character_panel.skill_panel_requested.emit()
	await process_frame
	_expect(manager.skill_panel.visible and manager.skill_panel.size == Vector2(240, 375),
		"查看技能应打开原尺寸非模态游戏窗口")
	_expect(manager.skill_panel._rows.size() == 13,
		"技能窗口应呈现十三项权威技能")
	var energy_row: Dictionary = manager.skill_panel._rows[0]
	_expect((energy_row["experience"] as Label).text == "0%",
		"技能第三列应显示当前经验百分比")
	var material_grant = panel_fixture.grant_loot({
		"loot_id": "monster.loot.runtime.material",
		"item_definition_id": "low_grade_biosilicon",
		"quantity": 2,
	})
	_expect(material_grant.is_ok, "地面材料应以同一领域物品进入背包")
	if material_grant.is_ok:
		manager.panel_session.apply_bundle(material_grant.value)
	await process_frame
	var material_view: InventoryItemView = null
	for raw_view: Node in manager.inventory_panel._item_canvas.get_children():
		var candidate := raw_view as InventoryItemView
		if candidate != null and candidate.item != null \
				and candidate.item.instance_id == "monster.loot.runtime.material":
			material_view = candidate
			break
	_expect(material_view != null and material_view.item is GameItem,
		"背包应直接消费拾取后的 GameItem 实例")
	if material_view != null:
		var material_icon := material_view.get_node("Icon") as TextureRect
		_expect(material_icon.texture != null,
			"低级生物硅进入背包后应使用 inventory 表现素材")
		_expect(material_view.size.is_equal_approx(InventoryPanel.CELL_SIZE) \
				and material_icon.size.is_equal_approx(
					InventoryPanel.CELL_SIZE - Vector2(10, 10)
				),
			"低级生物硅应进入统一五列八行单元格并保留 5px 内边距，实际 %s / %s" % [
				material_view.size, material_icon.size,
			])
	var damage_progress = panel_fixture.grant_skill_progression({
		"entity_id": "player.local",
		"source": "effective_damage",
		"skill_id": "energy_cannon",
		"damage": 7,
	})
	_expect(damage_progress.is_ok, "能量炮有效命中应进入权威技能成长链路")
	if damage_progress.is_ok:
		manager.panel_session.apply_bundle(damage_progress.value.panel_bundle)
	await process_frame
	_expect((energy_row["experience"] as Label).text == "3%",
		"七点有效伤害应立即刷新能量炮经验百分比")
	var driving_progress = panel_fixture.grant_skill_progression({
		"entity_id": "player.local",
		"source": "accepted_driving_movement",
		"skill_id": "driving",
		"distance": 2000.0,
		"vehicle_weight": 140.0,
	})
	_expect(driving_progress.is_ok, "服务器接受的驾驶距离应进入驾驶成长链路")
	if driving_progress.is_ok:
		manager.panel_session.apply_bundle(driving_progress.value.panel_bundle)
	await process_frame
	var driving_row: Dictionary = manager.skill_panel._rows[2]
	_expect((driving_row["experience"] as Label).text == "11%",
		"驾驶经验提速后应立即刷新为当前十一级可见进度")
	var inventory_item := manager.inventory_panel._item_canvas.get_child(0) as InventoryItemView
	var inventory_icon := inventory_item.get_node("Icon") as TextureRect
	_expect(inventory_icon.texture.get_size() == Vector2(36, 32),
		"背包仍应加载推进器 36x32 小图，而不是装备窗大图")
	_expect(inventory_item.item.definition_id == "beginner_engine" \
			and inventory_item.size.is_equal_approx(InventoryPanel.CELL_SIZE) \
			and inventory_icon.position == Vector2(5, 5) \
			and inventory_icon.size.is_equal_approx(
				InventoryPanel.CELL_SIZE - Vector2(10, 10)
			),
		"初级引擎也应使用统一单元格和 5px 内边距，实际 %s / %s / %s" % [
			inventory_item.size, inventory_icon.position, inventory_icon.size,
		])
	inventory_item.mouse_entered.emit()
	_expect(_is_item_highlighted(inventory_icon), "背包物品悬停应启用原版绿色发光")
	var legacy_tooltip := ItemHoverHighlightScript.active_tooltip()
	_expect(legacy_tooltip != null and legacy_tooltip.visible,
		"物品复杂说明应在 mouse_entered 当次立即显示")
	var tooltip_title := legacy_tooltip.get_node("Content/Title") as Label
	var tooltip_body := legacy_tooltip.get_node("Content/Body") as Label
	_expect(tooltip_title.get_theme_font_size("font_size") == 12 \
		and tooltip_body.get_theme_font_size("font_size") == 12,
		"物品说明标题和正文应保留 12px 字号")
	_expect((tooltip_title.get_theme_font("font") as SystemFont).font_weight == 800,
		"物品说明标题应使用 SETFONT2 对应的粗体字重")
	_expect(is_equal_approx(inventory_item.modulate.a, 1.0),
		"悬停材质不得覆盖背包拖拽透明度状态")
	inventory_item.mouse_exited.emit()
	_expect(not _is_item_highlighted(inventory_icon), "背包物品离开后应清除发光")
	_expect(legacy_tooltip.visible, "离开物品后应保留短暂时间供鼠标进入说明窗")
	await create_timer(0.12).timeout
	_expect(not legacy_tooltip.visible, "鼠标未进入说明窗时应在 100ms 检查后隐藏")
	var wearable_view: InventoryItemView
	for raw_view: Node in manager.inventory_panel._item_canvas.get_children():
		var candidate := raw_view as InventoryItemView
		if candidate != null and candidate.item != null \
				and candidate.item.instance_id == "inventory.training_shirt":
			wearable_view = candidate
			break
	_expect(wearable_view != null, "穿戴回归夹具应找到训练衫背包控件")
	if wearable_view != null:
		wearable_view.mouse_entered.emit()
		wearable_view.mouse_exited.emit()
	manager.inventory_panel._request_character_equip("inventory.training_shirt", "upper_body")
	await process_frame
	await create_timer(0.12).timeout
	legacy_tooltip = ItemHoverHighlightScript.active_tooltip()
	_expect(legacy_tooltip == null or not legacy_tooltip.visible,
		"换装重建悬浮目标后，旧延迟回调应安全关闭说明窗")
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
	_expect(chassis_visual.size == Vector2(199, 104), "新兵底盘应按 dialog 大图原始尺寸绘制")
	_expect(chassis_visual.texture.resource_path == "res://assets/ui/windows/vehicle/preview/chassis.png" \
			and chassis_visual.texture.get_size() == chassis_visual.size,
		"底盘必须使用真正的 199x104 装备窗大图，不能把背包小图拉伸成同样尺寸")
	_expect(weapon_visual.texture.resource_path == "res://assets/ui/windows/vehicle/preview/primary_weapon.png" \
			and weapon_visual.texture.get_size() == weapon_visual.size \
			and weapon_visual.size.x > 40,
		"能量炮必须使用独立大图按原生尺寸叠加，而不是 40x21 背包图")
	_expect(engine_visual.texture.resource_path == "res://assets/ui/windows/vehicle/preview/engine.png" \
			and engine_visual.texture.get_size() == Vector2(64, 57),
		"推进器必须使用独立的 64x57 装备窗图")
	_expect(engine_visual.position == Vector2(96, 360) \
			and engine_visual.size == Vector2(68, 68),
		"推进器应下移到标题下方，在底部槽内视觉居中")
	if "--capture-equipment" in OS.get_cmdline_user_args():
		manager.character_panel.hide()
		manager.inventory_panel.hide()
		manager.skill_panel.hide()
		manager.vehicle_panel.position = Vector2(24, 24)
		await process_frame
		await RenderingServer.frame_post_draw
		var capture_error := root.get_texture().get_image().save_png(
			"res://.godot/equipment_panel_regression.png"
		)
		_expect(capture_error == OK, "实际渲染截图应保存成功")
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
			moved_found = item.position == Vector2(92, 61)
	_expect(moved_found, "权威回包后物品应保持用户指定坐标，不自动整理到格子")
	manager.character_panel.position = Vector2(5000, 5000)
	manager.character_panel.clamp_to_viewport(Vector2(1280, 720))
	_expect(manager.character_panel.position == Vector2(925, 270), "拖动窗口必须限制在当前视口")
	_test_right_click_close(manager)
	_test_imported_dialog_geometry()
	_test_mining_arm_layering()
	_finish(manager)


## 检查原有及跨版本恢复的底盘使用各自大图尺寸、原点和背包图。
func _test_imported_dialog_geometry() -> void:
	var catalog := ItemCatalog.new()
	_expect(catalog.initialize().is_ok, "导入装备几何回归应加载目录")
	var projector := PlayerPanelProjector.new(catalog)
	for definition_id: String in [
		"glory_equipment_tank1_c2ba1ac5af", "glory_equipment_tank1000_27ae5e8059",
		"glory_equipment_finaltank_036fecf00f", "glory_equipment_finaltank_warrior_f6e890c3e9",
		"glory_equipment_finaltank_warrior_1_11d3a8cd2d", "glory_equipment_monarchfinaltank_6be62938f4",
		"glory_equipment_xmastank_d5d4117f3d", "glory_equipment_tankdragon_8ee199a53c",
	]:
		var equipment: Equipment = catalog.create(definition_id, {}).value
		var view := projector._equipment_view(equipment, "vehicle")
		var resolved := ItemPresentationTextureResolver.resolve(equipment.presentation_for("dialog"))
		_expect(not ItemPresentationTextureResolver.resolve(equipment.presentation_for("inventory")).is_empty(), "恢复底盘同时具备背包图标")
		var panel := VehicleEquipmentPanel.new()
		root.add_child(panel)
		panel.apply_snapshot({"equipped": [view]})
		var visual := panel._slot_root.get_child(0) as TextureRect
		var actual_atlas := visual.texture as AtlasTexture
		var expected_atlas := resolved["texture"] as AtlasTexture
		_expect(actual_atlas != null and expected_atlas != null \
				and actual_atlas.atlas.resource_path == expected_atlas.atlas.resource_path \
				and actual_atlas.region == expected_atlas.region \
				and visual.size == resolved["size"],
			"%s 应以自己的 dialog 贴图原生尺寸绘制" % definition_id)
		_expect(visual.position == Vector2(170, 200) + Vector2(resolved["origin"]),
			"%s 应按 ALE 原点叠加到安装锚点" % definition_id)
		panel.free()


## 验证旧 PNG 底盘及荣耀 ALE 底盘都不能盖住七档采掘臂。
func _test_mining_arm_layering() -> void:
	var catalog := ItemCatalog.new()
	_expect(catalog.initialize().is_ok, "采掘臂面板测试加载物品目录")
	var projector := PlayerPanelProjector.new(catalog)
	var merchant: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/commerce/weapon_merchant_v1.json").value
	for chassis_id: String in ["recruit_tank", "glory_equipment_tank1000_27ae5e8059"]:
		var chassis: Equipment = catalog.create(chassis_id, {}).value
		for arm_id: String in merchant.merchant.official_whitelist_ids.mining_arm:
			var arm: Equipment = catalog.create(arm_id, {}).value
			var panel := VehicleEquipmentPanel.new()
			root.add_child(panel)
			# 特意把底盘放在后面，确保不是碰巧依赖节点创建顺序。
			panel.apply_snapshot({"equipped": [projector._equipment_view(arm, "vehicle"), projector._equipment_view(chassis, "vehicle")]})
			var arm_visual := panel._slot_root.get_node("Location_1_%s" % arm_id) as TextureRect
			var chassis_visual := panel._slot_root.get_node("Location_0_%s" % chassis_id) as TextureRect
			_expect(arm_visual.z_index == 0 and chassis_visual.z_index == 0 and arm_visual.get_index() > chassis_visual.get_index(), "%s 必须覆盖 %s" % [arm_id, chassis_id])
			panel.free()


## 将窗口命令交给测试夹具并像客户端会话一样应用完整权威回包。
## [param command] 窗口生成的面板命令。
## [param manager] 消费权威面板快照的窗口管理器。
func _dispatch_panel_command(command: Dictionary, manager: GameWindowManager) -> void:
	var result = panel_fixture.execute(command)
	if result.is_ok:
		manager.panel_session.apply_bundle(result.value)
	else:
		failures.append("面板命令被测试权威拒绝：%s" % result.error_message)


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
	_expect(manager.inventory_panel.visible and manager.inventory_panel.context_menu.menu.visible,
		"右键命中背包物品时打开菜单并保留背包")
	manager.inventory_panel.context_menu.dismiss()

	manager.vehicle_panel.visible = true
	manager.skill_panel.visible = false
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
