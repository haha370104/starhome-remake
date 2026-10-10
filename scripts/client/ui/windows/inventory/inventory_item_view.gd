class_name InventoryItemView
extends Control

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
var _amount_label: Label
var _icon: TextureRect
var _hover_material: ShaderMaterial


## 使用权威物品快照配置一个可拖动背包视图。
## [param domain_item] 当前玩家背包内的具体领域物品实例。
## [param display_size] 五列八行网格中的统一单元格尺寸。
## [param padding] 图标相对单元格四边的留白。
## 设计：拖动时只显示跟随鼠标的物品，释放后由权威结果决定位置。
func configure(
	domain_item: GameItem,
	display_size: Vector2 = Vector2.ZERO,
	padding: float = 0.0,
) -> void:
	item = domain_item
	item_snapshot = item.to_view_dictionary()
	var inventory_presentation := item.presentation_for("inventory")
	var native_size := item.visual_size_for("inventory")
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
	elif item is EnhancementStone:
		item_tooltip = item.display_name + "\n" + EnhancementText.stone_description(item_snapshot) + "\n右键进入人物强化 / 合成"
	elif item is ConsumableItem:
		item_tooltip = item.display_name + "\n" + (item as ConsumableItem).use_description() + "\n右键使用 / 拆分 / 合并"
	gui_input.connect(_on_gui_input)

	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.position = Vector2(safe_padding, safe_padding)
	_icon.size = resolved_display_size - Vector2.ONE * safe_padding * 2.0
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_hover_material = ItemHoverHighlightScript.bind(self, _icon, item_tooltip)

	var amount := item.quantity
	_amount_label = Label.new()
	_amount_label.text = str(amount)
	_amount_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_amount_label.position = Vector2(-18, -16)
	_amount_label.size = Vector2(18, 16)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_amount_label.add_theme_font_size_override("font_size", 10.5)
	_amount_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.84))
	_amount_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_amount_label.add_theme_constant_override("outline_size", 2)
	_amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_amount_label)

	_amount_label.visible = amount > 1
	ItemTextureResolver.request(inventory_presentation, _apply_icon)

	if item is EnhancementStone and (item as EnhancementStone).family == "gem":
		var badge := Label.new()
		badge.name = "GemLevelBadge"
		badge.text = "L%d" % (item as EnhancementStone).rank
		badge.position = Vector2(0, 0)
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", Color("fff1ad"))
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(badge)

	if item.locked:
		modulate = Color(0.65, 0.65, 0.65)


## 切入右键操作前撤销拖动预览并收起悬停说明。
func prepare_context_menu() -> void:
	ItemHoverHighlight.dismiss_for(self)


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
		accept_event()


func _get_drag_data(at: Vector2) -> Variant:
	if item.locked: return null
	ItemHoverHighlight.dismiss_for(self)
	var preview := Control.new()
	preview.size = size
	preview.scale = get_global_transform().get_scale()
	preview.position = -at * preview.scale
	for child: Control in get_children(): preview.add_child(child.duplicate())
	var drag_root := Control.new()
	drag_root.add_child(preview)
	set_drag_preview(drag_root)
	hide()
	return {"instance_id": item.instance_id, "source": get_parent(), "offset": (size * 0.5 - at) * get_global_transform().get_scale()}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END: show()


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return get_parent()._can_drop_data(position + at, data)


func _drop_data(at: Vector2, data: Variant) -> void:
	get_parent()._drop_data(position + at, data)


## 异步图标就绪后只更新仍存活视图的纹理。
## [param visual] 已上传的共享图标。
func _apply_icon(visual: Dictionary) -> void:
	if is_queued_for_deletion() or _icon == null: return
	_icon.texture = visual.get("texture") as Texture2D


## 堆叠数量变化原位更新；其他物品属性变化交回完整视图配置。
## [param domain_item] 当前权威物品。
## 返回是否已复用视图。
func update_stack(domain_item: GameItem) -> bool:
	var snapshot := domain_item.to_view_dictionary()
	var previous := item_snapshot.duplicate(true)
	previous["amount"] = snapshot.amount
	previous["position_px"] = snapshot.position_px
	if previous != snapshot: return false
	item = domain_item
	item_snapshot = snapshot
	_amount_label.text = str(item.quantity)
	_amount_label.visible = item.quantity > 1
	return true
