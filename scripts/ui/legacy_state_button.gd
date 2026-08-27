class_name LegacyStateButton
extends Control

signal pressed

var textures: Dictionary = {}
var origins: Dictionary = {}
var image_rect: TextureRect
var hit_button: Button
var base_state := "normal"
var current_state := "normal"
var bounds_origin := Vector2.ZERO


## 按 [param definition] 中的状态贴图、尺寸与原点配置旧版像素按钮。
## Design: 控件以所有状态的联合边界作为点击区域，保证不同 origin 的帧切换时视觉锚点不跳动。
func configure(definition: Dictionary) -> void:
	textures.clear()
	origins.clear()
	var state_paths: Dictionary = definition.get("states", {})
	var state_origins: Dictionary = definition.get("state_origins", {})
	var state_sizes: Dictionary = definition.get("state_sizes", {})
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for state_name_value in state_paths:
		var state_name := String(state_name_value)
		var texture_path := String(state_paths[state_name])
		var texture := load(texture_path) as Texture2D if ResourceLoader.exists(texture_path) else null
		textures[state_name] = texture
		var origin := _vector_from_array(state_origins.get(state_name, []), Vector2.ZERO)
		var source_size := _vector_from_array(
			state_sizes.get(state_name, []),
			texture.get_size() if texture else Vector2(1, 1),
		)
		origins[state_name] = origin
		minimum = minimum.min(origin)
		maximum = maximum.max(origin + source_size)
	if textures.is_empty():
		textures["normal"] = null
		origins["normal"] = Vector2.ZERO
		minimum = Vector2.ZERO
		maximum = Vector2(31, 29)
	bounds_origin = minimum
	size = maximum - minimum
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP

	image_rect = TextureRect.new()
	image_rect.name = "StateImage"
	image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_rect.stretch_mode = TextureRect.STRETCH_KEEP
	image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image_rect)

	hit_button = Button.new()
	hit_button.name = "HitTarget"
	hit_button.flat = true
	hit_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit_button.focus_mode = Control.FOCUS_NONE
	hit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit_button.mouse_entered.connect(_on_mouse_entered)
	hit_button.mouse_exited.connect(_on_mouse_exited)
	hit_button.button_down.connect(_on_button_down)
	hit_button.button_up.connect(_on_button_up)
	hit_button.pressed.connect(func() -> void: pressed.emit())
	add_child(hit_button)
	set_base_state("normal" if textures.has("normal") else String(textures.keys()[0]))


## 将素材边界原点对齐到 [param source_anchor] 指定的旧客户端坐标。
func place_at(source_anchor: Vector2) -> void:
	position = source_anchor + bounds_origin


## 将 [param state_name] 设为按钮的常驻状态，并立即刷新显示。
func set_base_state(state_name: String) -> void:
	base_state = state_name if textures.has(state_name) else "normal"
	set_visual_state(base_state)


## 显示 [param state_name] 对应的贴图状态；缺失时回退到常驻状态。
func set_visual_state(state_name: String) -> void:
	if not textures.has(state_name):
		state_name = base_state
	current_state = state_name
	var texture := textures.get(state_name) as Texture2D
	image_rect.texture = texture
	image_rect.position = Vector2(origins.get(state_name, Vector2.ZERO)) - bounds_origin
	image_rect.size = texture.get_size() if texture else Vector2.ZERO


## 在指针进入点击区域时切换到悬停视觉状态。
func _on_mouse_entered() -> void:
	set_visual_state("hover" if textures.has("hover") else base_state)


## 在指针离开点击区域时恢复常驻视觉状态。
func _on_mouse_exited() -> void:
	set_visual_state(base_state)


## 在按钮按下时切换到按压视觉状态。
func _on_button_down() -> void:
	set_visual_state("pressed" if textures.has("pressed") else base_state)


## 在按钮松开时根据指针位置恢复悬停或常驻状态。
func _on_button_up() -> void:
	set_visual_state("hover" if textures.has("hover") and hit_button.is_hovered() else base_state)


## 将 [param value] 的前两个数组元素转换为向量，格式无效时使用 [param fallback]。
## Returns 转换后的二维向量。
func _vector_from_array(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
