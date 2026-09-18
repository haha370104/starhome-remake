class_name SamaEffectController
extends Node

const PRESENTATION_PATH := "res://data/presentation/sama_effects_v1.json"
static var _config: Dictionary = {}
static var _art: Dictionary = {}
var _world: Node2D
var _player: Node2D
var _pulses: Array[Dictionary] = []
var _statuses: Dictionary = {}


## 绑定世界和本地车身，表现资源只从本地审核目录读取。
## [param world] 特效父层。[param player] 本地车身节点。
func configure(world: Node2D, player: Node2D) -> void:
	_world = world
	_player = player
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRESENTATION_PATH))
		if parsed is Dictionary: _config = parsed


## 在已去重的权威触发后播放原版两排四段脉冲与能力提示。
## [param event] 仅含能力种类和世界坐标的权威事件。
func present_activation(event: Dictionary) -> void:
	var point := _point(event.get("origin"))
	var direction := _point(event.get("direction"))
	var kind := String(event.get("kind", ""))
	if not point.is_finite() or not direction.is_finite() or direction.is_zero_approx() or kind not in ["pulse", "piercing", "fission"]: return
	var text := CombatDamageFloat.new()
	text.position = point + Vector2(0, -50)
	_world.add_child(text)
	text.present_status({"pulse":"脉冲攻击", "piercing":"聚能穿透", "fission":"核变反应"}[kind], Color("79d9ff"))
	if kind != "pulse": return
	var wrapper := Node2D.new()
	wrapper.name = "SamaPulse"
	wrapper.position = point + direction.normalized() * 200
	wrapper.rotation = direction.angle()
	wrapper.scale = Vector2.ONE * float(_config.pulse.scale)
	_world.add_child(wrapper)
	var sprites: Array[Sprite2D] = []
	for row in 2:
		for index in 4:
			var sprite := Sprite2D.new()
			sprite.centered = false
			sprite.position = Vector2((index - 1.5) * 100, -155 if row == 0 else 155)
			wrapper.add_child(sprite)
			sprites.append(sprite)
	_pulses.append({"node":wrapper, "sprites":sprites, "age":0.0})
	_update_pulse(_pulses.back())


## 根据权威剩余时间显示原版聚能和核变状态图，丢失来源时立即移除。
## [param snapshot] 战斗快照。
func apply_snapshot(snapshot: Dictionary) -> void:
	var observed := PackedStringArray()
	for row: Dictionary in snapshot.get("local_sama_effects", []):
		var kind := String(row.get("kind", ""))
		var remaining := float(row.get("remaining_seconds", 0))
		if kind not in ["piercing", "fission"] or not is_finite(remaining) or remaining <= 0: continue
		observed.append(kind)
		if not _statuses.has(kind):
			var wrapper := Node2D.new()
			wrapper.name = "SamaStatus_" + kind
			var icon := Sprite2D.new()
			var art := _load_art(kind)
			icon.texture = art.textures[0]
			icon.scale = Vector2.ONE * (26.0 / maxf(icon.texture.get_width(), icon.texture.get_height()))
			wrapper.add_child(icon)
			var label := Label.new()
			label.position = Vector2(-20,14)
			label.size = Vector2(40,22)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_constant_override("outline_size", 4)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			wrapper.add_child(label)
			_world.add_child(wrapper)
			_statuses[kind] = {"node":wrapper,"label":label,"remaining":remaining}
		_statuses[kind].remaining = remaining
	for kind: String in _statuses.keys():
		if kind not in observed:
			_statuses[kind].node.queue_free()
			_statuses.erase(kind)
	_update_statuses(0)


## 统一推进轻量表现时钟，伤害和技能生效时间仍由服务器决定。
## [param delta] 本帧秒数。
func _process(delta: float) -> void:
	advance(delta)


## 推进两排动画并清理到期脉冲及状态图。
## [param delta] 本帧秒数。
func advance(delta: float) -> void:
	if _world == null or not is_instance_valid(_world): return
	for index in range(_pulses.size() - 1, -1, -1):
		var pulse := _pulses[index]
		pulse.age += delta
		if pulse.age >= float(_config.pulse.lifetime):
			pulse.node.queue_free()
			_pulses.remove_at(index)
		else: _update_pulse(pulse)
	_update_statuses(delta)


## 保留ALE逐帧原点，避免动画尺寸变化造成视觉抖动。
## [param pulse] 当前双排脉冲实例。
func _update_pulse(pulse: Dictionary) -> void:
	for index in pulse.sprites.size():
		var second: bool = index >= 4
		var elapsed := float(pulse.age) - (float(_config.pulse.second_delay) if second else 0.0)
		var sprite: Sprite2D = pulse.sprites[index]
		sprite.visible = elapsed >= 0
		if elapsed < 0: continue
		var art := _load_art("pulse_end" if second else "pulse_start")
		var frame := mini(art.textures.size() - 1, floori(elapsed * float(_config.pulse.fps)))
		sprite.texture = art.textures[frame]
		sprite.offset = art.offsets[frame]


## 跟随当前可见车身，并只做剩余时间的视觉倒计时。
## [param delta] 本帧经过的秒数。
func _update_statuses(delta: float) -> void:
	if _player == null or not is_instance_valid(_player): return
	var index := 0
	for kind: String in _statuses.keys():
		var state: Dictionary = _statuses[kind]
		state.remaining = maxf(0, float(state.remaining) - delta)
		if state.remaining <= 0:
			state.node.queue_free()
			_statuses.erase(kind)
			continue
		state.node.position = _world.to_local(_player.global_position) + Vector2(-16 + index * 34, -94)
		state.label.text = "%ds" % ceili(state.remaining)
		index += 1


## 按需缓存本地图像与原点，跨地图复用已导入纹理。
## [param kind] 本地已知效果种类。
## 返回纹理序列和原点序列。
static func _load_art(kind: String) -> Dictionary:
	if _art.has(kind): return _art[kind]
	var textures: Array[Texture2D] = []
	var offsets: Array[Vector2] = []
	for row: Dictionary in _config.effects[kind]:
		textures.append(load(String(row.texture)) as Texture2D)
		offsets.append(Vector2(row.offset[0], row.offset[1]))
	_art[kind] = {"textures":textures,"offsets":offsets}
	return _art[kind]


## 将受控事件中的坐标对转换为有限向量。
## [param value] 原始坐标。
## 返回有限坐标或无效标记。
static func _point(value: Variant) -> Vector2:
	return Vector2(value[0], value[1]) if value is Array and value.size() == 2 else Vector2.INF


## 地图卸载时清除挂在世界层的临时节点。
func _exit_tree() -> void:
	for pulse: Dictionary in _pulses:
		if is_instance_valid(pulse.node): pulse.node.queue_free()
	for state: Dictionary in _statuses.values():
		if is_instance_valid(state.node): state.node.queue_free()
	_pulses.clear()
	_statuses.clear()
