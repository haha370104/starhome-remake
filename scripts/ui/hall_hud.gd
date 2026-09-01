class_name HallHud
extends CanvasLayer

signal popup_closed
signal npc_action_requested(action_id: String)
signal hud_action_requested(action_id: String)

const HUD_MANIFEST_PATH := "res://data/ui/free_hud_assets.json"
const HudStateScript := preload("res://scripts/ui/hud_state.gd")
const TopMenuScript := preload("res://scripts/ui/free_top_menu.gd")
const BottomMainBarScript := preload("res://scripts/ui/free_bottom_main_bar.gd")
const ShortcutBarScript := preload("res://scripts/ui/free_shortcut_bar.gd")
const MinimapDockScript := preload("res://scripts/ui/free_minimap_dock.gd")
const LEGACY_PANEL_FONT := preload("res://assets/ui/fonts/legacy_panel_font.tres")
const CentralSystemMessageFeedScript := preload(
	"res://scripts/ui/central_system_message_feed.gd"
)

var root_control: Control
var hint_label: Label
var popup: PanelContainer
var popup_title: Label
var popup_body: Label
var popup_actions: VBoxContainer
var minimap_player_dot: ColorRect
var top_menu: Control
var minimap_dock: Control
var shortcut_bar: Control
var bottom_main_bar: Control
var state: HudState
var asset_manifest: Dictionary = {}
var system_message_feed: CentralSystemMessageFeed


## 执行 `configure` 对应的模块操作。
## [param world_map_size] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param minimap_texture] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param map_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：本节点只负责组合免费版 HUD 组件与转发业务信号，共享状态集中在 `HudState`。
func configure(world_map_size: Vector2, minimap_texture: Texture2D, map_name := "") -> void:
	layer = 50
	name = "HallHud"
	state = HudStateScript.new()
	asset_manifest = _load_manifest()
	set_process_input(true)

	root_control = Control.new()
	root_control.name = "HudRoot"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	state.hud_visibility_changed.connect(func(value: bool) -> void: root_control.visible = value)

	top_menu = TopMenuScript.new()
	top_menu.configure(asset_manifest.get("top_menu", {}), state)
	top_menu.action_requested.connect(_emit_hud_action)
	root_control.add_child(top_menu)

	minimap_dock = MinimapDockScript.new()
	minimap_dock.configure(
		world_map_size,
		minimap_texture,
		map_name,
		asset_manifest.get("minimap_chrome", {}),
		state,
	)
	minimap_dock.layout_width_changed.connect(top_menu.set_minimap_width)
	root_control.add_child(minimap_dock)
	minimap_player_dot = minimap_dock.player_dot
	top_menu.set_minimap_width(minimap_dock.size.x)

	bottom_main_bar = BottomMainBarScript.new()
	bottom_main_bar.configure(
		asset_manifest.get("bottom_main", {}),
		asset_manifest.get("general_shortcut", {}),
		state,
	)
	bottom_main_bar.action_requested.connect(_emit_hud_action)
	root_control.add_child(bottom_main_bar)

	shortcut_bar = ShortcutBarScript.new()
	shortcut_bar.configure(
		asset_manifest.get("general_shortcut", {}),
		state,
	)
	root_control.add_child(shortcut_bar)

	_build_popup()
	_build_hint_label()
	_build_system_message_feed()


## 将系统提示加入顺序队列；每次技能升级都获得完整展示时间。
## [param message] 待展示的非空本地化系统消息。
func show_system_message(message: String) -> void:
	system_message_feed.show_message(message)


## 创建中央系统消息表现器；队列、停留、上浮和淡出均由组件独立负责。
func _build_system_message_feed() -> void:
	system_message_feed = CentralSystemMessageFeedScript.new()
	system_message_feed.configure()
	root_control.add_child(system_message_feed)


## 执行 `update_player_dot` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func update_player_dot(world_position: Vector2) -> void:
	state.set_player_position(world_position)


## 执行 `set_map` 对应的模块操作。
## [param world_map_size] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param minimap_texture] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param map_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：地图切换只更新地图业务内容，免费版 HUD 外框及玩家设置状态保持不变。
## [param transitions] 当前地图的传送点定义，交给小地图绘制浅绿色标记。
func set_map(
	world_map_size: Vector2,
	minimap_texture: Texture2D,
	map_name: String,
	transitions: Array[MapTransition] = [],
) -> void:
	if minimap_dock:
		minimap_dock.set_map(world_map_size, minimap_texture, map_name, transitions)


## 执行 `set_reserve_energy` 对应的模块操作。
## [param current] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param capacity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_reserve_energy(current: float, capacity: float) -> void:
	state.set_reserve_energy(current, capacity)


## 用战车 Location 13 的实际装备刷新唯一战术操作槽。
## [param action_id] 当前战术装备对应的操作标识。
## [param count] 该战术物品的权威可用数量；负数表示不显示数量。
func set_tactical_action(action_id: String, count := -1) -> void:
	state.set_tactical_action(action_id, count)


## 执行 `set_vehicle_combat_state` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_vehicle_combat_state(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	state.set_vehicle_health(int(snapshot.get("health", 0)), int(snapshot.get("max_health", 0)))
	state.set_working_energy(
		float(snapshot.get("working_energy", 0.0)),
		float(snapshot.get("working_energy_capacity", 0.0)),
	)
	state.set_reserve_energy(
		float(snapshot.get("reserve_energy", 0.0)),
		float(snapshot.get("reserve_energy_capacity", 0.0)),
	)


## 执行 `show_npc_popup` 对应的模块操作。
## [param interaction] NPC 名称、正文和原版纵向动作项。
## [param screen_position] NPC 当前屏幕坐标；菜单按原版在其左上方约 30 像素弹出。
func show_npc_popup(interaction: Dictionary, screen_position := Vector2(-1, -1)) -> void:
	popup_title.text = String(interaction.get("title", "NPC"))
	popup_body.text = String(interaction.get("body", ""))
	for child in popup_actions.get_children():
		child.free()
	var action_count := 0
	for action_value in interaction.get("actions", []):
		var action_id := ""
		var action_label := ""
		if action_value is Dictionary:
			action_id = String(action_value.get("id", "action"))
			action_label = String(action_value.get("label", action_id))
		else:
			action_id = String(action_value)
			action_label = action_id
		var action_button := Button.new()
		action_button.text = action_label
		action_button.custom_minimum_size = Vector2(106, 23)
		action_button.add_theme_font_override("font", LEGACY_PANEL_FONT)
		action_button.add_theme_font_size_override("font_size", 13)
		action_button.add_theme_color_override("font_color", Color("faf0c8"))
		action_button.add_theme_color_override("font_hover_color", Color.YELLOW)
		action_button.add_theme_stylebox_override(
			"normal", _button_style(Color.TRANSPARENT, Color.TRANSPARENT)
		)
		action_button.add_theme_stylebox_override(
			"hover", _button_style(Color("123d5d"), Color("47cdf2"))
		)
		action_button.add_theme_stylebox_override(
			"pressed", _button_style(Color("03121d"), Color.YELLOW)
		)
		action_button.pressed.connect(_emit_npc_action.bind(action_id))
		popup_actions.add_child(action_button)
		action_count += 1
	popup.size = Vector2(118, 12 + action_count * 23)
	var requested := screen_position - Vector2(30, 30)
	if screen_position.x < 0.0:
		requested = (get_viewport().get_visible_rect().size - popup.size) * 0.5
	var viewport_size := get_viewport().get_visible_rect().size
	popup.position = Vector2(
		clampf(requested.x, 0.0, maxf(0.0, viewport_size.x - popup.size.x)),
		clampf(requested.y, 0.0, maxf(0.0, viewport_size.y - popup.size.y)),
	)
	popup.visible = true


## 隐藏当前 NPC 弹窗，并在状态实际改变时通知调用方。
func hide_popup() -> void:
	if not popup.visible:
		return
	popup.visible = false
	popup_closed.emit()


## 执行 `emit_npc_action` 对应的模块操作。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _emit_npc_action(action_id: String) -> void:
	npc_action_requested.emit(action_id)


## 执行 `emit_hud_action` 对应的模块操作。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _emit_hud_action(action_id: String) -> void:
	hud_action_requested.emit(action_id)
	if hint_label and action_id not in ["character", "inventory", "vehicle_equipment"]:
		hint_label.text = "%s 功能待接入" % action_id


## 读取并校验免费版 HUD 素材清单。
## 返回该函数计算、查询或操作得到的结果。
func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(HUD_MANIFEST_PATH):
		push_error("Free HUD manifest is missing: %s" % HUD_MANIFEST_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HUD_MANIFEST_PATH))
	if not parsed is Dictionary:
		push_error("Free HUD manifest is invalid: %s" % HUD_MANIFEST_PATH)
		return {}
	return parsed


## 创建左上角的移动与交互操作提示。
func _build_hint_label() -> void:
	hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.text = "右键移动 · 左键点击 NPC"
	hint_label.position = Vector2(12, 4)
	hint_label.add_theme_font_size_override("font_size", 17)
	hint_label.add_theme_color_override("font_color", Color(0.68, 0.95, 1.0))
	hint_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint_label.add_theme_constant_override("shadow_offset_x", 2)
	hint_label.add_theme_constant_override("shadow_offset_y", 2)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(hint_label)


## 创建原版 BasePOPMenu 风格的 NPC 动作菜单；标题和正文仅保留为语义数据。
func _build_popup() -> void:
	popup = PanelContainer.new()
	popup.name = "NpcPopup"
	popup.size = Vector2(118, 80)
	popup.add_theme_stylebox_override("panel", _panel_style(Color("00121eea"), Color("2996c9")))
	popup.visible = false
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(popup)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 5)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 6)
	popup.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)
	popup_title = Label.new()
	popup_title.name = "Title"
	popup_title.visible = false
	column.add_child(popup_title)
	popup_body = Label.new()
	popup_body.name = "Body"
	popup_body.visible = false
	column.add_child(popup_body)
	popup_actions = VBoxContainer.new()
	popup_actions.name = "Actions"
	popup_actions.add_theme_constant_override("separation", 0)
	column.add_child(popup_actions)


## 右键点菜单关闭且不触发移动；点菜单外则先关闭，再由地图处理移动。
func _input(event: InputEvent) -> void:
	if not popup or not popup.visible or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return
	var inside := popup.get_global_rect().has_point(mouse_event.position)
	hide_popup()
	if inside:
		get_viewport().set_input_as_handled()


## 执行 `panel_style` 对应的模块操作。
## [param background] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param border] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(1)
	style.shadow_color = Color(0, 0, 0, 0.7)
	style.shadow_size = 3
	return style


func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	return style
