class_name EquipmentLayerView
extends TextureRect

const TextureResolver := preload("res://scripts/client/presentation/items/item_presentation_texture_resolver.gd")
const TooltipFormatter := preload("res://scripts/client/ui/windows/equipment_tooltip_formatter.gd")
const HoverHighlight := preload("res://scripts/client/ui/windows/item_hover_highlight.gd")


## 解析装备面板图并按原始锚点或固定矩形显示，同时绑定统一属性提示。
## [param equipment] 已投影的装备展示快照；不读取玩家或会话。
## [param default_anchor] 缺少显式锚点时采用的面板坐标。
## [param fixed_rect] 非空时在指定槽位居中，否则保持原图尺寸和 ALE 原点。
## 返回图像是否可用；调用方负责释放失败的组件。
func configure(equipment: Dictionary, default_anchor: Vector2, fixed_rect := Rect2()) -> bool:
	var presentation: Dictionary = equipment.get("dialog_presentation", {})
	if presentation.is_empty():
		presentation = {"dialog_texture": equipment.get("dialog_texture", "")}
	var resolved := TextureResolver.resolve(presentation)
	if resolved.is_empty():
		return false
	texture = resolved["texture"] as Texture2D
	var anchor: Array = equipment.get("dialog_anchor", [default_anchor.x, default_anchor.y])
	var origin: Vector2 = resolved.get("origin", Vector2.ZERO)
	if presentation.has("dialog_origin"):
		var origin_value: Array = equipment.get("dialog_origin", [0, 0])
		origin = Vector2(float(origin_value[0]), float(origin_value[1]))
	position = Vector2(float(anchor[0]), float(anchor[1])) + origin
	size = texture.get_size()
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP
	if fixed_rect.has_area():
		position = fixed_rect.position
		size = fixed_rect.size
		stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_STOP
	HoverHighlight.bind(self, self, TooltipFormatter.format(equipment))
	return true
