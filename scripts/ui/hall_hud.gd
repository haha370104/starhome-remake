class_name HallHud
extends CanvasLayer

signal popup_closed
signal npc_action_requested(action_id: String)

const UI_ROOT := "res://assets/ui/hud/"
const ITEM_ROOT := "res://assets/items/weapons/"
const UI_CELL := Vector2(31.0, 29.0)

const TOP_BUTTONS := [
	"btn_guard", "btn_help", "btn_creatnpc", "btn_backhome", "btn_repaireself",
	"btn_systemmsg", "yshxcountbtn", "btn_joinvr", "btn_looktem", "btn_ng",
	"btn_topmenuanni", "FBBtn", "explore", "mercenarymissionwnd", "PivotControlWnd",
]
const BOTTOM_BUTTONS := [
	"humanwnd", "humanequip", "humanbag", "playertask",
	"playerfriend", "spacemap", "skysource", "system",
]

var map_size := Vector2.ONE
var root_control: Control
var hint_label: Label
var popup: PanelContainer
var popup_title: Label
var popup_body: Label
var popup_actions: VBoxContainer
var minimap_player_dot: ColorRect


func configure(world_map_size: Vector2, minimap_texture: Texture2D) -> void:
	map_size = world_map_size
	layer = 50
	name = "HallHud"
	root_control = Control.new()
	root_control.name = "HUDRoot"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	_build_top_menu()
	_build_minimap(minimap_texture)
	_build_bottom_bar()
	_build_popup()

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


func update_player_dot(world_position: Vector2) -> void:
	if not minimap_player_dot:
		return
	minimap_player_dot.position = (
		Vector2(4, 4) + world_position / map_size * Vector2(148, 148) - Vector2(3, 3)
	)


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


func hide_popup() -> void:
	if not popup.visible:
		return
	popup.visible = false
	popup_closed.emit()


func _emit_npc_action(action_id: String) -> void:
	npc_action_requested.emit(action_id)


func _build_top_menu() -> void:
	var grid := GridContainer.new()
	grid.name = "TopMenu"
	grid.columns = 10
	grid.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grid.offset_left = -480
	grid.offset_right = -170
	grid.offset_top = 0
	grid.offset_bottom = 58
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(grid)
	for resource_name in TOP_BUTTONS:
		grid.add_child(_state_button("top_%s" % resource_name, "顶部菜单（功能待接入）"))
	for index in range(20 - TOP_BUTTONS.size()):
		var spacer := Panel.new()
		spacer.custom_minimum_size = UI_CELL
		spacer.add_theme_stylebox_override(
			"panel", _panel_style(Color("153c65"), Color("245f91"), 1, 0)
		)
		grid.add_child(spacer)


func _build_minimap(minimap_texture: Texture2D) -> void:
	var panel := Panel.new()
	panel.name = "Minimap"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -164
	panel.offset_right = -8
	panel.offset_top = 0
	panel.offset_bottom = 191
	panel.add_theme_stylebox_override(
		"panel", _panel_style(Color("071723"), Color("19b9d7"), 2, 2)
	)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(panel)

	var map := TextureRect.new()
	map.texture = minimap_texture
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map.position = Vector2(4, 4)
	map.size = Vector2(148, 148)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(map)
	for dot_position in [Vector2(570, 1040), Vector2(845, 1190), Vector2(1045, 835), Vector2(1290, 1060)]:
		var dot := ColorRect.new()
		dot.color = Color(0.15, 0.95, 1.0)
		dot.size = Vector2(3, 3)
		dot.position = Vector2(4, 4) + dot_position / map_size * Vector2(148, 148)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(dot)

	minimap_player_dot = ColorRect.new()
	minimap_player_dot.name = "PlayerDot"
	minimap_player_dot.color = Color(0.2, 1.0, 0.35)
	minimap_player_dot.size = Vector2(6, 6)
	minimap_player_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(minimap_player_dot)

	var title := Label.new()
	title.text = "易安港基地大厅一层"
	title.position = Vector2(4, 157)
	title.size = Vector2(148, 27)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.25, 1.0, 0.35))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)


func _build_bottom_bar() -> void:
	var rail := Panel.new()
	rail.name = "BottomRail"
	rail.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	rail.offset_top = -31
	rail.offset_bottom = 0
	rail.add_theme_stylebox_override(
		"panel", _panel_style(Color("071a31"), Color("36bfe9"), 2, 0)
	)
	rail.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(rail)

	var shortcut := TextureRect.new()
	shortcut.name = "ShortcutBar"
	shortcut.texture = load(UI_ROOT + "shortcutbar.png")
	shortcut.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shortcut.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shortcut.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	shortcut.offset_left = -249
	shortcut.offset_right = 249
	shortcut.offset_top = -80
	shortcut.offset_bottom = -32
	shortcut.mouse_filter = Control.MOUSE_FILTER_STOP
	shortcut.tooltip_text = "快捷栏（功能待接入）"
	root_control.add_child(shortcut)

	var weapons := HBoxContainer.new()
	weapons.name = "Weapons"
	weapons.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	weapons.offset_left = 154
	weapons.offset_right = 402
	weapons.offset_top = -30
	weapons.offset_bottom = -1
	weapons.add_theme_constant_override("separation", 2)
	root_control.add_child(weapons)
	weapons.add_child(_weapon_slot(load(ITEM_ROOT + "energy_cannon.png"), "能量炮", "", true))
	weapons.add_child(_weapon_slot(load(ITEM_ROOT + "missile.png"), "导弹", "1700", false))
	weapons.add_child(_weapon_slot(null, "其他", "", false))

	var menus := HBoxContainer.new()
	menus.name = "BottomMenus"
	menus.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	menus.offset_left = -256
	menus.offset_right = -8
	menus.offset_top = -30
	menus.offset_bottom = -1
	menus.add_theme_constant_override("separation", 0)
	root_control.add_child(menus)
	for resource_name in BOTTOM_BUTTONS:
		menus.add_child(_state_button("menu_btn_%s" % resource_name, "底部菜单（功能待接入）"))


func _state_button(prefix: String, tooltip: String) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = load(UI_ROOT + "%s_normal.png" % prefix)
	button.texture_hover = load(UI_ROOT + "%s_hover.png" % prefix)
	button.texture_pressed = load(UI_ROOT + "%s_pressed.png" % prefix)
	button.ignore_texture_size = true
	button.custom_minimum_size = UI_CELL
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.tooltip_text = tooltip
	return button


func _weapon_slot(icon_texture: Texture2D, label_text: String, count_text: String, active: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(78, UI_CELL.y)
	button.tooltip_text = "%s（功能待接入）" % label_text
	button.add_theme_stylebox_override(
		"normal",
		_panel_style(
			Color("133756") if active else Color("0a1725"),
			Color("55edff") if active else Color("31556d"),
			2,
			2,
		),
	)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	if icon_texture:
		var icon := TextureRect.new()
		icon.texture = icon_texture
		icon.custom_minimum_size = Vector2(25, 25)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	var name_label := Label.new()
	name_label.text = label_text + ("\n" + count_text if not count_text.is_empty() else "")
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override(
		"font_color", Color(1.0, 0.2, 0.15) if not count_text.is_empty() else Color.WHITE
	)
	row.add_child(name_label)
	return button


func _build_popup() -> void:
	popup = PanelContainer.new()
	popup.name = "NpcPopup"
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.offset_left = -155
	popup.offset_right = 155
	popup.offset_top = -125
	popup.offset_bottom = 125
	popup.add_theme_stylebox_override(
		"panel", _panel_style(Color("0a1b2b"), Color("39d5ff"), 2, 6)
	)
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


func _panel_style(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style
