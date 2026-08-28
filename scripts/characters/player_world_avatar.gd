class_name PlayerWorldAvatar
extends Node2D

const WorldCharacterScript := preload("res://scripts/characters/world_character.gd")
const CombatVisualPresenterScript := preload(
	"res://scripts/client/presentation/combat/combat_visual_presenter.gd"
)

const CHARACTER_KIND := &"character"
const COMBAT_ACTOR_KIND := &"combat_actor"

var presentation_kind: StringName = CHARACTER_KIND
var combat_actor_id: StringName = &""
var human_character: Node2D
var combat_presenter: Node2D
var combat_name_label: Label

var _combat_manifest: Dictionary = {}
var _current_action := &"stand"
var _current_direction := 6
var _animation_speed_scale := 1.0


## 构建共享人形角色与按需隐藏的战斗载具表现。
## [param character_set] 继续由现有 `CharacterFactory` 生成，避免大厅角色形成第二套实现。
## [param combat_manifest] 只接受业务化战斗角色清单；来源旧名不得进入本节点。
## [param display_name]、[param name_color] 是两种外观共享的玩家身份样式。
## [param human_name_offset] 保留现有人形名称标签的业务偏移。
## Returns 两套表现均可初始化时返回 `OK`，否则返回对应错误码。
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
	return OK


## 验证地图 [param presentation] 是否能由当前玩家外观节点完整消费。
## Returns 人形声明或清单中真实存在的战斗角色返回 `OK`，否则返回稳定错误码。
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


## 原子采用地图 [param presentation]，在人形与战斗载具之间切换。
## Returns 声明通过验证且目标角色所有资源可加载时返回 `OK`。
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
	_apply_active_pose()
	return OK


## 把 [param action] 与八向 [param direction] 投影到当前活动表现。
func set_action(action: String, direction: int) -> void:
	_current_action = StringName(action)
	_current_direction = posmod(direction, 8)
	_apply_active_pose()


## 设置人形动画倍率；战车继续采用其荣耀来源清单中的独立帧率。
## [param value] 仅影响人形角色，避免玩家成长配置篡改装备素材帧率证据。
func set_animation_speed_scale(value: float) -> void:
	_animation_speed_scale = maxf(value, 0.0)
	if human_character != null:
		human_character.set_animation_speed_scale(_animation_speed_scale)


## 报告当前地图是否正在使用战斗载具外观。
## Returns 活动表现为已配置战斗角色时返回 `true`。
func is_combat_actor_active() -> bool:
	return (
		presentation_kind == COMBAT_ACTOR_KIND
		and combat_presenter != null
		and combat_presenter.current_actor_id != &""
	)


## 每帧只推进当前可见的战斗角色动画。
## [param delta] 由节点树提供的秒数。
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


## 将移动协议动作 [param action] 归一化为现有人形角色的 `stand/move`。
## Returns 移动类动作返回 `move`，其余返回 `stand`。
func _human_action(action: StringName) -> String:
	return "move" if action in [&"move", &"moving", &"walk", &"walking", &"run", &"running"] else "stand"


## 将移动协议动作 [param action] 归一化为战斗表现的 `idle/move/attack`。
## Returns 已知战斗动作，未知动作安全回退为 `idle`。
func _combat_action(action: StringName) -> StringName:
	if action in [&"move", &"moving", &"walk", &"walking", &"run", &"running"]:
		return &"move"
	if action == &"attack":
		return &"attack"
	return &"idle"


## 创建战车模式独立名称标签，使隐藏人形时玩家身份仍然可见。
## [param display_name] 与 [param name_color] 沿用玩家共享身份样式。
## Returns 以战车脚点为锚的名称标签。
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
