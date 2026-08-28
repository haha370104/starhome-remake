class_name PlayerWorldAvatar
extends Node2D

const WorldCharacterScript := preload("res://scripts/characters/world_character.gd")
const CombatVisualPresenterScript := preload(
	"res://scripts/client/presentation/combat/combat_visual_presenter.gd"
)
const WorldCombatStatusBarScript := preload(
	"res://scripts/client/presentation/combat/world_combat_status_bar.gd"
)

const CHARACTER_KIND := &"character"
const COMBAT_ACTOR_KIND := &"combat_actor"

var presentation_kind: StringName = CHARACTER_KIND
var combat_actor_id: StringName = &""
var human_character: Node2D
var combat_presenter: Node2D
var combat_name_label: Label
var combat_status_bar: WorldCombatStatusBar

var _combat_manifest: Dictionary = {}
var _current_action := &"stand"
var _current_direction := 6
var _animation_speed_scale := 1.0


## 构建共享人形角色与按需隐藏的战斗载具表现。
## [param character_set] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param combat_manifest] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param display_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param name_color] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param human_name_offset] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func configure(
	character_set: Dictionary,
	combat_manifest: Dictionary,
	display_name: String,
	name_color: Color,
	human_name_offset: Vector2,
) -> Error:
	if character_set.is_empty() or combat_manifest.is_empty():
		return ERR_INVALID_PARAMETER
	_combat_manifest = combat_manifest.duplicate(true)

	human_character = WorldCharacterScript.new()
	human_character.name = "HumanCharacter"
	human_character.configure(
		character_set,
		display_name,
		name_color,
		human_name_offset,
	)
	add_child(human_character)

	combat_presenter = CombatVisualPresenterScript.new()
	combat_presenter.name = "CombatActor"
	var presenter_error: Error = combat_presenter.configure(_combat_manifest)
	if presenter_error != OK:
		return presenter_error
	combat_presenter.visible = false
	add_child(combat_presenter)

	combat_name_label = _build_name_label(display_name, name_color)
	combat_name_label.visible = false
	add_child(combat_name_label)
	combat_status_bar = WorldCombatStatusBarScript.new()
	combat_status_bar.name = "CombatStatusBar"
	combat_status_bar.configure(50.0, true, Vector2(0, 45))
	combat_status_bar.visible = false
	add_child(combat_status_bar)
	return OK


## 执行 `validate_map_presentation` 对应的模块操作。
## [param presentation] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func validate_map_presentation(presentation: Dictionary) -> Error:
	var kind := StringName(presentation.get("kind", CHARACTER_KIND))
	if kind == CHARACTER_KIND:
		return OK
	if kind != COMBAT_ACTOR_KIND:
		return ERR_INVALID_DATA
	var manifest_path := String(presentation.get("manifest", ""))
	if manifest_path != "res://assets/equipment_world/combat_visual_manifest.json":
		return ERR_INVALID_DATA
	var actor_id := StringName(presentation.get("actor_id", &""))
	var actors_value: Variant = _combat_manifest.get("actors", {})
	if actor_id == &"" or not actors_value is Dictionary:
		return ERR_INVALID_DATA
	return OK if (actors_value as Dictionary).has(String(actor_id)) else ERR_DOES_NOT_EXIST


## 执行 `apply_map_presentation` 对应的模块操作。
## [param presentation] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func apply_map_presentation(presentation: Dictionary) -> Error:
	var validation_error := validate_map_presentation(presentation)
	if validation_error != OK:
		return validation_error
	var kind := StringName(presentation.get("kind", CHARACTER_KIND))
	if kind == CHARACTER_KIND:
		presentation_kind = CHARACTER_KIND
		combat_actor_id = &""
		human_character.visible = true
		combat_presenter.visible = false
		combat_name_label.visible = false
		combat_status_bar.visible = false
		_apply_active_pose()
		return OK

	var requested_actor := StringName(presentation.get("actor_id", &""))
	if combat_presenter.current_actor_id != requested_actor:
		var present_error: Error = combat_presenter.present_actor(requested_actor)
		if present_error != OK:
			return present_error
	presentation_kind = COMBAT_ACTOR_KIND
	combat_actor_id = requested_actor
	human_character.visible = false
	combat_presenter.visible = true
	combat_name_label.visible = true
	combat_status_bar.visible = true
	_apply_active_pose()
	return OK


## 执行 `set_action` 对应的模块操作。
## [param action] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param direction] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_action(action: String, direction: int) -> void:
	_current_action = StringName(action)
	_current_direction = posmod(direction, 8)
	_apply_active_pose()


## 执行 `set_combat_layer_pose` 对应的模块操作。
## [param layer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param action] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param direction] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func set_combat_layer_pose(layer_id: StringName, action: StringName, direction: int) -> bool:
	if not is_combat_actor_active():
		return false
	return (
		combat_presenter.set_layer_direction(layer_id, direction)
		and combat_presenter.set_layer_action(layer_id, action)
	)


## 执行 `clear_combat_layer_action` 对应的模块操作。
## [param layer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func clear_combat_layer_action(layer_id: StringName) -> void:
	if combat_presenter != null:
		combat_presenter.clear_layer_action(layer_id)


## 执行 `set_combat_status` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_combat_status(snapshot: Dictionary) -> void:
	if combat_status_bar == null or snapshot.is_empty():
		return
	combat_status_bar.set_health(float(snapshot.get("health", 0)), float(snapshot.get("max_health", 1)))
	combat_status_bar.set_energy(
		float(snapshot.get("working_energy", 0.0)),
		float(snapshot.get("max_working_energy", 1.0)),
	)


## 设置人形动画倍率；战车继续采用其荣耀来源清单中的独立帧率。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_animation_speed_scale(value: float) -> void:
	_animation_speed_scale = maxf(value, 0.0)
	if human_character != null:
		human_character.set_animation_speed_scale(_animation_speed_scale)


## 报告当前地图是否正在使用战斗载具外观。
## 返回该函数计算、查询或操作得到的结果。
func is_combat_actor_active() -> bool:
	return (
		presentation_kind == COMBAT_ACTOR_KIND
		and combat_presenter != null
		and combat_presenter.current_actor_id != &""
	)


## 每帧只推进当前可见的战斗角色动画。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _process(delta: float) -> void:
	if presentation_kind == COMBAT_ACTOR_KIND and combat_presenter != null:
		combat_presenter.advance(delta)


## 将已缓存动作与朝向同步到当前可见表现。
func _apply_active_pose() -> void:
	if presentation_kind == CHARACTER_KIND:
		if human_character != null:
			human_character.set_action(_human_action(_current_action), _current_direction)
		return
	if combat_presenter == null or combat_presenter.current_actor_id == &"":
		return
	combat_presenter.set_direction(_current_direction)
	combat_presenter.set_action(_combat_action(_current_action))


## 执行 `human_action` 对应的模块操作。
## [param action] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _human_action(action: StringName) -> String:
	return "move" if action in [&"move", &"moving", &"walk", &"walking", &"run", &"running"] else "stand"


## 执行 `combat_action` 对应的模块操作。
## [param action] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _combat_action(action: StringName) -> StringName:
	if action in [&"move", &"moving", &"walk", &"walking", &"run", &"running"]:
		return &"move"
	if action == &"attack":
		return &"attack"
	return &"idle"


## 创建战车模式独立名称标签，使隐藏人形时玩家身份仍然可见。
## [param display_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param name_color] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _build_name_label(display_name: String, name_color: Color) -> Label:
	var label := Label.new()
	label.name = "CombatNameLabel"
	label.text = display_name
	label.position = Vector2(-65, -72)
	label.size = Vector2(130, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", name_color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
