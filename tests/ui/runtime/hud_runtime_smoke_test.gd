extends SceneTree

const HallHudScript := preload("res://scripts/ui/hall_hud.gd")
const MANIFEST_PATH := "res://data/ui/free_hud_assets.json"
const MINIMAP_PATH := "res://assets/maps/yian_harbor/hall_floor_1/minimap.jpg"

var failures: PackedStringArray = []
var assertions := 0


## 延迟启动 HUD 运行时冒烟测试，避免在 SceneTree 初始化期间操作根视口。
## 设计：测试主体需要跨渲染帧等待布局完成，因此从延迟调用进入异步流程。
func _initialize() -> void:
	call_deferred("_run")


## 实例化免费版 HUD，验证素材来源、像素尺寸、锚定、状态同步与窗口缩放行为。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_expect(manifest.get("asset_release", "") == "free_hud", "HUD 运行时清单必须是免费版 HUD")
	_expect(manifest.get("source_release", "") == "starhome_lz_fr", "HUD 外观素材必须登记为免费版来源")
	_expect(manifest["bottom_main"]["reserve_energy"]["frames"] is Dictionary, "储备能量帧应以语义字典存储")
	_expect(manifest["minimap_chrome"].get("map_content_source", "") == "current_glory_map", "小地图内容仍必须来自荣耀版地图")

	var hud: CanvasLayer = HallHudScript.new()
	hud.configure(Vector2(1944, 1920), load(MINIMAP_PATH), "龙之城基地大厅一层")
	root.add_child(hud)
	await process_frame
	await process_frame
	_assert_1280_layout(hud)
	_assert_state_updates(hud)
	_assert_primary_devices(hud)
	_assert_npc_popup(hud)
	_assert_map_rebinding(hud)
	_assert_minimap_modes(hud)
	_assert_transition_markers(hud)

	root.size = Vector2i(1600, 900)
	await process_frame
	await process_frame
	_assert_1600_layout(hud)

	if failures.is_empty():
		print("HUD_RUNTIME_SMOKE_OK (%d assertions)" % assertions)
		hud.free()
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	hud.free()
	quit(1)


## 执行 `assert_1280_layout` 对应的模块操作。
## [param hud] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _assert_1280_layout(hud: CanvasLayer) -> void:
	_expect(hud.top_menu.size == Vector2(330, 54), "顶部菜单必须保持 330×54 原始像素")
	_expect(hud.top_menu.position == Vector2(825, 0), "1280 宽时顶部菜单应在 125 宽小地图左侧贴顶")
	_expect(hud.top_menu.action_buttons.size() == 5, "顶部菜单必须由首批 5 个独立按钮组成")
	_expect(hud.minimap_dock.position == Vector2(1155, 0), "125 宽免费版小地图应贴右上")
	_expect(hud.minimap_dock.size == Vector2(125, 165), "免费版小地图小模式必须为 125×165")
	_expect(hud.minimap_dock.map_viewport.size == Vector2(120, 120), "小地图裁剪视口必须为 120×120")
	_expect(hud.minimap_dock.map_image.texture.get_size() == Vector2(300, 300), "必须消费当前荣耀版专用 300×300 小地图 JPG")
	_expect(hud.bottom_main_bar.position == Vector2(0, 691), "底部主栏应以 29 像素高度吸底")
	_expect(hud.bottom_main_bar.size == Vector2(1280, 29), "底部停靠容器应横跨窗口而不拉伸中央素材")
	_expect(hud.bottom_main_bar.design_surface.size == Vector2(1024, 29), "底栏中央设计面必须保持 1024×29")
	_expect(hud.bottom_main_bar.design_surface.position == Vector2(128, 0), "1280 宽时 1024 像素底栏应水平居中")
	_expect(hud.bottom_main_bar.weapon_buttons.size() == 1, "未装战术设备时底栏只应显示能量炮")
	_expect(not hud.bottom_main_bar.weapon_buttons.has("missile"), "未装导弹时不得显示导弹图标")
	_expect(hud.shortcut_bar.size == Vector2(415, 40), "快捷栏必须保持 415×40 原始像素")
	_expect(hud.shortcut_bar.position == Vector2(432.5, 651), "快捷栏应紧贴底部主栏上方居中")
	hud.show_system_message("测试系统提示")
	var message_center: Vector2 = hud.system_message_feed.message_label.get_global_rect().get_center()
	_expect(message_center.is_equal_approx(Vector2(640, 360)),
		"系统提示应以 1280×720 游戏画面的正中心为初始锚点")


## 执行 `assert_state_updates` 对应的模块操作。
## [param hud] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _assert_state_updates(hud: CanvasLayer) -> void:
	var dot_before: Vector2 = hud.minimap_dock.player_dot.position
	hud.update_player_dot(Vector2(972, 960))
	_expect(hud.minimap_dock.player_dot.position == dot_before, "小模式的玩家点必须固定在视口中心")
	_expect(hud.minimap_dock.map_image.position == Vector2(-90, -90), "小地图底图应围绕玩家反向移动")
	_expect(hud.minimap_dock.coordinate_label.text == "972,960", "坐标文本应订阅玩家位置")

	hud.set_reserve_energy(5000, 10000)
	_expect(is_equal_approx(hud.bottom_main_bar.reserve_energy_clip.size.x, 161.5), "储备能量条应按 323×比例裁剪")
	_expect(hud.bottom_main_bar.reserve_energy_clip.tooltip_text.contains("5000/10000"), "储备能量提示应显示权威状态")

	hud.state.set_selected_action_slot("missile")
	_expect(hud.state.selected_action_slot == "energy_cannon", "不能选择尚未安装的导弹")
	hud.set_tactical_action("missile", 17)
	_expect(hud.bottom_main_bar.weapon_buttons.size() == 2, "装入导弹后应创建唯一战术槽")
	_expect(hud.bottom_main_bar.tactical_count_label.text == "17", "导弹数量应由装备状态驱动")
	hud.state.set_selected_action_slot("missile")
	_expect(hud.bottom_main_bar.weapon_buttons["missile"].base_state == "selected", "导弹槽应切换到选中帧")
	_expect(hud.bottom_main_bar.weapon_buttons["energy_cannon"].base_state == "normal", "切换武器后能量炮应恢复普通帧")
	hud.set_tactical_action("rocket_launcher")
	_expect(not hud.bottom_main_bar.weapon_buttons.has("missile"), "互斥槽换装后必须移除旧导弹按钮")
	_expect(hud.state.selected_action_slot == "energy_cannon", "移除当前战术武器后应回退能量炮")
	hud.state.set_selected_action_slot("rocket_launcher")
	_expect(hud.state.selected_action_slot == "rocket_launcher", "战术槽应选择实际安装的火箭炮")
	_expect(hud.bottom_main_bar.weapon_buttons["rocket_launcher"].hit_button.tooltip_text == "火箭炮", "火箭炮按钮应说明用途")
	hud.set_tactical_action("")
	_expect(hud.bottom_main_bar.weapon_buttons.size() == 1, "卸下战术设备后必须清空第二格")

	hud.state.set_shortcut_visible(false)
	_expect(not hud.shortcut_bar.visible, "快捷栏状态为隐藏时不应渲染本体")
	_expect(hud.bottom_main_bar.shortcut_visibility_buttons["expand"].visible, "快捷栏隐藏时底栏应显示展开按钮")
	hud.state.set_shortcut_visible(true)


## 验证 NPC 菜单采用原版贴身纵向动作布局，并支持右键关闭。
## [param hud] 测试中的真实 HUD 节点。
func _assert_npc_popup(hud: CanvasLayer) -> void:
	hud.show_npc_popup({
		"title": "武器商人",
		"actions": [
			{"id": "buy", "label": "买东西"},
			{"id": "sell", "label": "卖东西"},
			{"id": "task", "label": "中级任务"},
		],
	}, Vector2(600, 300))
	_expect(hud.popup.position == Vector2(570, 270), "NPC 菜单应在 NPC 屏幕坐标左上 30 像素弹出")
	_expect(hud.popup_actions.get_child_count() == 3, "武器商人应显示三个独立文字动作")
	_expect(not hud.popup_title.visible and not hud.popup_body.visible,
		"原版 BasePOPMenu 不应显示现代化标题和正文")
	var task_button := hud.popup_actions.get_child(2) as Button
	_expect(task_button.text == "中级任务" and task_button.size.y == 23,
		"第三项应以原版紧凑行显示中级任务")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = hud.popup.get_global_rect().get_center()
	hud._input(right_click)
	_expect(not hud.popup.visible, "右键点击 NPC 菜单应关闭菜单")


## 执行 `assert_map_rebinding` 对应的模块操作。
## [param hud] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _assert_map_rebinding(hud: CanvasLayer) -> void:
	var minimap_texture: Texture2D = hud.minimap_dock.map_image.texture
	hud.set_map(Vector2(3888, 3840), minimap_texture, "G08")
	_expect(hud.minimap_dock.world_size == Vector2(3888, 3840), "切图后必须采用新世界尺寸")
	_expect(hud.minimap_dock.map_name_label.text == "G08", "切图后必须更新地图名")
	_expect(hud.minimap_dock.map_image.position == Vector2(-15, -15), "切图后应按新尺寸重新投影现有玩家点")
	_expect(hud.shortcut_bar.visible, "切图不得重置玩家的 HUD 显隐偏好")
	hud.set_map(Vector2(1944, 1920), minimap_texture, "龙之城基地大厅一层")


## 验证主装置换装和卸下后图标、提示、选中态同步，不影响战术槽。
## [param hud] 真实 HUD 实例。
func _assert_primary_devices(hud: CanvasLayer) -> void:
	hud.set_tactical_action("missile")
	hud.state.set_selected_action_slot("energy_cannon")
	for device_kind: String in ["mining_arm", "repair_arm", "energy_cannon"]:
		hud.set_primary_device(device_kind)
		var button: Control = hud.bottom_main_bar.weapon_buttons.energy_cannon
		_expect(button.current_state == "selected", "换装后保留主槽选中态")
		_expect(button.image_rect.texture.resource_path.contains("/%s/selected.png" % device_kind), "主槽应显示该类型原版图标")
		_expect(button.size == Vector2(29, 22), "主槽图标保持免费版像素尺寸")
		_expect(button.hit_button.tooltip_text == FreeBottomMainBar.WEAPON_TOOLTIPS[device_kind], "悬浮名称同步装备类别")
		hud.state.set_selected_action_slot("missile")
		_expect(button.current_state == "normal", "选中战术槽后主装置切回未选中图")
		button.pressed.emit()
		_expect(hud.state.selected_action_slot == "energy_cannon", "不同工程臂图标仍操作同一主槽")
	hud.set_primary_device("")
	_expect(not hud.bottom_main_bar.weapon_buttons.has("energy_cannon"), "卸下主装置不能遗留炮图标")
	_expect(hud.bottom_main_bar.weapon_buttons.has("missile"), "卸下主装置不影响战术槽")
	hud.set_primary_device("energy_cannon")
	hud.set_tactical_action("")


## 执行 `assert_minimap_modes` 对应的模块操作。
## [param hud] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _assert_minimap_modes(hud: CanvasLayer) -> void:
	hud.state.set_minimap_size("large")
	_expect(hud.minimap_dock.map_viewport.size == Vector2(300, 300), "大地图模式必须直接使用专用 JPG 原始尺寸")
	_expect(hud.minimap_dock.size == Vector2(300, 341), "大地图总尺寸应由 300 像素地图与 41 像素控制区组成")
	_expect(hud.top_menu.position == Vector2(650, 0), "小地图变宽时顶部菜单应重新锚定在其左侧")

	hud.state.set_minimap_collapsed(true)
	_expect(hud.minimap_dock.size == Vector2(125, 41), "小地图收起后必须仅保留 125×41 控制区")
	_expect(not hud.minimap_dock.map_viewport.visible, "小地图收起后应隐藏地图视口")
	_expect(hud.top_menu.position == Vector2(825, 0), "小地图收起后顶部菜单应按 125 像素宽度重新锚定")

	hud.state.set_top_menu_expanded(false)
	_expect(hud.top_menu.size == Vector2(12, 26), "顶部菜单收起后必须为 12×26")
	_expect(hud.top_menu.position == Vector2(1143, 0), "收起的顶部菜单仍应紧贴小地图左边")
	hud.state.set_top_menu_expanded(true)
	hud.state.set_minimap_collapsed(false)
	hud.state.set_minimap_size("small")


## 验证传送点的投影、禁用过滤、滚动、折叠和切图清理。
## [param hud] 测试中的真实 HUD 节点。
func _assert_transition_markers(hud: CanvasLayer) -> void:
	var first := MapTransition.new()
	first.source_anchor = Vector2(972, 960)
	var disabled := MapTransition.new()
	disabled.source_anchor = Vector2(100, 100)
	disabled.enabled = false
	var duplicate := MapTransition.new()
	duplicate.source_anchor = first.source_anchor
	var transitions: Array[MapTransition] = [first, disabled, duplicate]
	var dock: Control = hud.minimap_dock
	hud.set_map(Vector2(1944, 1920), dock.map_image.texture, "标记测试", transitions)
	var points: PackedVector2Array = dock.marker_layer.marker_positions()
	_expect(points == PackedVector2Array([Vector2(150, 150)]), "传送点必须按世界尺寸投影、过滤禁用并去重")
	_expect(dock.marker_layer.MARKER_COLOR == Color(0.65, 1.0, 0.7, 1.0), "传送点必须使用浅绿色")
	hud.update_player_dot(Vector2(972, 960))
	_expect(dock.marker_layer.global_position + points[0] == dock.map_viewport.global_position + Vector2(60, 60), "小模式下标记必须随地图滚动到正确位置")
	hud.state.set_minimap_size("large")
	_expect(dock.marker_layer.marker_positions() == points, "大小模式切换不得缩放或移动地图内标记")
	hud.state.set_minimap_collapsed(true)
	_expect(not dock.marker_layer.is_visible_in_tree(), "收起小地图必须隐藏传送标记")
	hud.state.set_minimap_collapsed(false)
	hud.state.set_minimap_size("small")
	hud.set_map(Vector2(1944, 1920), dock.map_image.texture, "龙之城基地大厅一层")
	_expect(dock.marker_layer.marker_positions().is_empty(), "切到没有出口的地图必须清除旧传送标记")


## 执行 `assert_1600_layout` 对应的模块操作。
## [param hud] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _assert_1600_layout(hud: CanvasLayer) -> void:
	_expect(hud.top_menu.position == Vector2(1145, 0), "1600 宽时顶部菜单应仍位于小地图左侧")
	_expect(hud.top_menu.size == Vector2(330, 54), "窗口变大不得缩放顶部菜单")
	_expect(hud.minimap_dock.position == Vector2(1475, 0), "窗口变大后小地图仍应贴右上")
	_expect(hud.bottom_main_bar.position == Vector2(0, 871), "窗口变大后 29 像素底栏仍应吸底")
	_expect(hud.bottom_main_bar.design_surface.position == Vector2(288, 0), "1600 宽时 1024 像素底栏应水平居中")
	_expect(hud.bottom_main_bar.design_surface.size == Vector2(1024, 29), "窗口变大不得拉伸底栏中央素材")
	_expect(hud.shortcut_bar.position == Vector2(592.5, 831), "窗口变大后快捷栏仍应吸底居中")
	_expect(hud.shortcut_bar.size == Vector2(415, 40), "窗口变大不得缩放快捷栏")
	var message_center: Vector2 = hud.system_message_feed.message_label.get_global_rect().get_center()
	_expect(message_center.is_equal_approx(Vector2(800, 450)),
		"窗口放大后系统提示仍应重新锚定屏幕正中心")


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
