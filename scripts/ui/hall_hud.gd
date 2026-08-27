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


## 以 [param world_map_size]、[param minimap_texture] 和 [param map_name] 组装大厅 HUD。
## Design: 本节点只负责组合免费版 HUD 组件与转发业务信号，共享状态集中在 `HudState`。
func configure(world_map_size: Vector2, minimap_texture: Texture2D, map_name := "") -> void:
	layer = 50
	name = "HallHud"
	state = HudStateScript.new()
	asset_manifest = _load_manifest()

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


## 将玩家世界坐标 [param world_position] 推送给小地图状态。
func update_player_dot(world_position: Vector2) -> void:
	state.set_player_position(world_position)


## 原子替换小地图使用的 [param world_map_size]、[param minimap_texture] 与 [param map_name]。
## Design: 地图切换只更新地图业务内容，免费版 HUD 外框及玩家设置状态保持不变。
func set_map(
	world_map_size: Vector2,
	minimap_texture: Texture2D,
	map_name: String,
) -> void:
	if minimap_dock:
		minimap_dock.set_map(world_map_size, minimap_texture, map_name)


## 将当前储备能量 [param current] 与容量 [param capacity] 推送给 HUD 状态。
func set_reserve_energy(current: float, capacity: float) -> void:
	state.set_reserve_energy(current, capacity)


## 根据 [param interaction] 的标题、正文和动作列表显示 NPC 交互弹窗。
func show_npc_popup(interaction: Dictionary) -> void:
	popup_title.text = String(interaction.get("title", "NPC"))
	popup_body.text = String(interaction.get("body", ""))
	for child in popup_actions.get_children():
		child.free()
	for action_value in interaction.get("actions", []):
		var action_id := String(action_value)
		var action_label := String(action_value)
		if action_value is Dictionary:
			action_id = String(action_value.get("id", "action"))
			action_label = String(action_value.get("label", action_id))
		var action_button := Button.new()
		action_button.text = action_label
		action_button.custom_minimum_size = Vector2(0, 36)
		action_button.pressed.connect(_emit_npc_action.bind(action_id))
		popup_actions.add_child(action_button)
	popup.visible = true


## 隐藏当前 NPC 弹窗，并在状态实际改变时通知调用方。
func hide_popup() -> void:
	if not popup.visible:
		return
	popup.visible = false
	popup_closed.emit()


## 将弹窗动作 [param action_id] 转发为 NPC 业务信号。
func _emit_npc_action(action_id: String) -> void:
	npc_action_requested.emit(action_id)


## 将 HUD 动作 [param action_id] 转发给业务层，并显示尚未接入提示。
func _emit_hud_action(action_id: String) -> void:
	hud_action_requested.emit(action_id)
	if hint_label:
		hint_label.text = "%s 功能待接入" % action_id


## 读取并校验免费版 HUD 素材清单。
## Returns 解析成功时返回清单字典，失败时返回空字典并报告错误。
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


## 创建由标题、正文、动态动作区和关闭按钮组成的 NPC 弹窗。
func _build_popup() -> void:
	popup = PanelContainer.new()
	popup.name = "NpcPopup"
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.offset_left = -155
	popup.offset_right = 155
	popup.offset_top = -125
	popup.offset_bottom = 125
	popup.add_theme_stylebox_override("panel", _panel_style(Color("0a1b2b"), Color("39d5ff")))
	popup.visible = false
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(popup)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	popup.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	popup_title = Label.new()
	popup_title.name = "Title"
	popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_title.add_theme_font_size_override("font_size", 23)
	popup_title.add_theme_color_override("font_color", Color("65eaff"))
	column.add_child(popup_title)
	popup_body = Label.new()
	popup_body.name = "Body"
	popup_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_body.add_theme_font_size_override("font_size", 16)
	column.add_child(popup_body)
	popup_actions = VBoxContainer.new()
	popup_actions.name = "Actions"
	popup_actions.add_theme_constant_override("separation", 6)
	column.add_child(popup_actions)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(hide_popup)
	column.add_child(close_button)


## 使用 [param background] 和 [param border] 创建弹窗面板样式。
## Returns 新建的圆角面板样式。
func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style
