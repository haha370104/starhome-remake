class_name GeneratorStatusView
extends Node2D

class Effect extends RefCounted:
	var sprite: Sprite2D
	var frames: Array = []
	var elapsed := 0.0
	var fps := 12.5

static var _definitions: Dictionary = {}
static var _animations: Dictionary = {}
var _repository: RefCounted
var _active: Dictionary[String, Effect] = {}
var _label: Label


## 复用怪物原版技能动画和共享帧缓存；状态节点跟随所属怪物，不另存世界位置。
## [param repository] 当前场景已有的ALE资源仓储。
func configure(repository: RefCounted) -> void:
	_repository = repository
	if _definitions.is_empty():
		var loaded := JsonConfigLoader.load_dictionary("res://data/presentation/generator_effects_v1.json")
		if loaded.is_ok: _definitions = loaded.value.get("effects", {})
	_label = Label.new()
	_label.position = Vector2(-70, 31)
	_label.size = Vector2(140, 20)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", preload("res://assets/ui/fonts/legacy_panel_font.tres"))
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color("ffd38a"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	_label.z_index = 21
	_label.visible = false
	add_child(_label)


## 按权威有效状态集合增删节点，重复快照不重启动画，未知类型不猜资源。
## [param raw_ids] 权威快照的稳定状态身份数组。
func apply_statuses(raw_ids: Variant) -> void:
	var ids := PackedStringArray()
	if raw_ids is Array or raw_ids is PackedStringArray:
		for value: Variant in raw_ids:
			if value is String and _definitions.has(value) and value not in ids: ids.append(value)
	for id: String in _active.keys():
		if id not in ids:
			_active[id].sprite.free()
			_active.erase(id)
	var labels := PackedStringArray()
	for id: String in ids:
		labels.append(String(_definitions[id].label))
		if not _active.has(id): _create_effect(id)
	_label.text = " · ".join(labels)
	_label.visible = not ids.is_empty()


## 从已审计的精确资源引用创建一次动画，所有怪物复用相同帧纹理。
## [param id] 已确认的状态身份。
func _create_effect(id: String) -> void:
	if _repository == null: return
	var definition: Dictionary = _definitions[id]
	if not _animations.has(id):
		var animation: Dictionary = _repository.load_animation(String(definition.source_animation))
		var frames: Array = animation.get("frames", [])
		if frames.size() != int(definition.frames): return
		_animations[id] = frames
	var effect := Effect.new()
	effect.frames = _animations[id]
	effect.fps = float(definition.fps)
	effect.sprite = Sprite2D.new()
	effect.sprite.name = id
	effect.sprite.centered = false
	effect.sprite.position = Vector2(float(definition.offset[0]), float(definition.offset[1]))
	effect.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	effect.sprite.z_index = 2
	add_child(effect.sprite)
	_active[id] = effect
	_apply_frame(effect)


## 每个目标从自身首次受影响时开始动画，服务器仍拥有持续时间和伤害结算。
## [param elapsed] 本帧秒数。
func advance(elapsed: float) -> void:
	for effect: Effect in _active.values():
		effect.elapsed += maxf(0, elapsed)
		_apply_frame(effect)


## 保留原版每帧原点，避免动画尺寸变化令命中特效漂移。
## [param effect] 当前循环动画状态。
func _apply_frame(effect: Effect) -> void:
	var frame: Dictionary = effect.frames[posmod(floori(effect.elapsed * effect.fps), effect.frames.size())]
	effect.sprite.texture = frame.texture
	effect.sprite.offset = frame.origin
