class_name WorldCharacter
extends Node2D

var body := AnimatedSprite2D.new()
var equipment := AnimatedSprite2D.new()
var shadow := AnimatedSprite2D.new()
var name_label := Label.new()
var body_offsets: Dictionary
var equipment_offsets: Dictionary
var shadow_offsets: Dictionary
var current_action := "stand"
var current_direction := 6


## 配置并初始化 `configure` 对应的模块状态。
## [param character_set] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param display_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param name_color] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param name_offset] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func configure(
	character_set: Dictionary,
	display_name: String,
	name_color: Color,
	name_offset: Vector2,
) -> void:
	body_offsets = character_set["body_offsets"]
	equipment_offsets = character_set["equipment_offsets"]
	shadow_offsets = character_set["shadow_offsets"]

	shadow.name = "Shadow"
	shadow.sprite_frames = character_set["shadow_frames"]
	shadow.centered = false
	# All visual layers deliberately share the character's canvas Z. Their
	# insertion order composes one character, while the parent remains the sole
	# unit participating in the world's Y sort.
	shadow.z_index = 0
	add_child(shadow)

	body.name = "Body"
	body.sprite_frames = character_set["body_frames"]
	body.centered = false
	add_child(body)

	equipment.name = "Equipment"
	equipment.sprite_frames = character_set["equipment_frames"]
	equipment.centered = false
	equipment.z_index = 0
	add_child(equipment)

	name_label.name = "NameLabel"
	name_label.text = display_name
	name_label.position = name_offset
	name_label.size = Vector2(130, 24)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", name_color)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 2)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.z_index = 0
	add_child(name_label)
	set_action("stand", 6)


## 设置或恢复 `set_action` 对应的模块状态。
## [param action] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param direction] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_action(action: String, direction: int) -> void:
	current_action = action
	current_direction = direction
	body.offset = body_offsets[action]
	equipment.offset = equipment_offsets[action]
	shadow.offset = shadow_offsets[action]
	var animation := StringName("%s_%d" % [action, direction])
	if body.animation != animation or not body.is_playing():
		body.play(animation)
	if equipment.animation != animation or not equipment.is_playing():
		equipment.play(animation)
	if shadow.animation != animation or not shadow.is_playing():
		shadow.play(animation)


## 设置或恢复 `set_animation_speed_scale` 对应的模块状态。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_animation_speed_scale(value: float) -> void:
	body.speed_scale = value
	equipment.speed_scale = value
	shadow.speed_scale = value


## 替换人物当前上衣的八方向动画资源。
## [param character_set] CharacterFactory 为具体 Clothing 构建的角色图层集合。
func set_equipment_set(character_set: Dictionary) -> void:
	equipment.sprite_frames = character_set["equipment_frames"]
	equipment_offsets = character_set["equipment_offsets"]
	equipment.visible = true
	set_action(current_action, current_direction)


## 设置人物服装层是否可见；裸模和阴影始终保留。
## [param visible] 当前 CharacterEquipment 是否在上衣槽拥有服装。
func set_equipment_visible(visible: bool) -> void:
	equipment.visible = visible
