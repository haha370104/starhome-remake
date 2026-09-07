class_name InventoryItemView
extends Control

signal move_requested(instance_id: String, position_px: Vector2i)
signal equip_requested(instance_id: String, location: int)
signal character_equip_requested(instance_id: String, slot_id: String)

const ItemHoverHighlightScript := preload(
	"res://scripts/client/ui/windows/item_hover_highlight.gd"
)
const ItemTextureResolver := preload(
	"res://scripts/client/presentation/items/item_presentation_texture_resolver.gd"
)
const TooltipFormatter := preload("res://scripts/client/ui/windows/equipment_tooltip_formatter.gd")

var item_snapshot: Dictionary = {}
var item: GameItem
var _dragging := false
var _drag_offset := Vector2.ZERO
var _icon: TextureRect
var _hover_material: ShaderMaterial


## 使用权威物品快照配置一个可拖动背包视图。
## [param domain_item] 当前玩家背包内的具体领域物品实例。
## [param display_size] 五列八行网格中的统一单元格尺寸。
## [param padding] 图标相对单元格四边的留白。
## 设计：拖动只移动本地幽灵节点，释放后提交意图；下一次权威快照决定最终位置。
func configure(
	domain_item: GameItem,
	display_size: Vector2 = Vector2.ZERO,
	padding: float = 0.0,
) -> void:
	item = domain_item
	item_snapshot = item.to_view_dictionary()
	var inventory_presentation := item.presentation_for("inventory")
	var resolved_visual := ItemTextureResolver.resolve(inventory_presentation)
	var native_size := item.visual_size_for("inventory")
	if not resolved_visual.is_empty() and not inventory_presentation.has("native_size"):
		native_size = Vector2i(resolved_visual["size"])
	var resolved_display_size := display_size if display_size.x > 0.0 and display_size.y > 0.0 \
		else Vector2(native_size)
	var safe_padding := clampf(
		padding, 0.0, minf(resolved_display_size.x, resolved_display_size.y) * 0.5
	)
	size = resolved_display_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var item_tooltip := "%s\n%s" % [
		item.display_name,
		item.description,
	]
	if item is Equipment:
		item_tooltip = TooltipFormatter.format(item.to_view_dictionary(), "双击装备")
	gui_input.connect(_on_gui_input)

	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture = resolved_visual.get("texture") as Texture2D
	_icon.position = Vector2(safe_padding, safe_padding)
	_icon.size = resolved_display_size - Vector2.ONE * safe_padding * 2.0
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_hover_material = ItemHoverHighlightScript.bind(self, _icon, item_tooltip)

	var amount := item.quantity
	if amount > 1:
		var amount_label := Label.new()
		amount_label.text = str(amount)
		amount_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		amount_label.position = Vector2(-18, -16)
		amount_label.size = Vector2(18, 16)
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_label.add_theme_font_size_override("font_size", 11)
		amount_label.add_theme_color_override("font_outline_color", Color.BLACK)
		amount_label.add_theme_constant_override("outline_size", 2)
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(amount_label)

	if item.locked:
		modulate = Color(0.65, 0.65, 0.65)


## 处理物品拖动和双击装备手势。
## [param event] Godot GUI 输入事件。
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click and event.pressed:
			var location := int(item_snapshot.get("equipment_location", -1))
			if location >= 0:
				equip_requested.emit(String(item_snapshot.get("instance_id", "")), location)
			elif not String(item_snapshot.get("character_slot", "")).is_empty():
				character_equip_requested.emit(
					String(item_snapshot.get("instance_id", "")),
					String(item_snapshot.get("character_slot", "")),
				)
			accept_event()
			return
		if event.pressed and not item.locked:
			_dragging = true
			_drag_offset = event.position
			modulate.a = 0.65
		else:
			if _dragging:
				var requested := Vector2i((position + event.position - _drag_offset).round())
				move_requested.emit(String(item_snapshot.get("instance_id", "")), requested)
			_dragging = false
			modulate.a = 1.0
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		position += event.relative
		accept_event()
