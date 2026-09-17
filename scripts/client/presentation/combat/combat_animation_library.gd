class_name CombatAnimationLibrary
extends RefCounted

static var _repository: AleSpriteRepository
static var _cache: Dictionary = {}


## 把离线核对的武器弹体关联追加到既有表现清单，不改变权威伤害规则。
## [param base] 已导入的新手弹道、烟雾和爆炸模板。
## 返回含全部可用武器弹体的隔离清单。
static func with_weapon_bindings(base: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	var loaded := JsonConfigLoader.load_dictionary("res://data/presentation/weapon_visual_bindings_v1.json")
	if not loaded.is_ok:
		return result
	var templates := {"energy_cannon": "recruit_energy_cannon", "missile": "starter_missile", "rocket_launcher": "starter_rocket_launcher"}
	for definition_id: String in loaded.value.weapons:
		var binding: Dictionary = loaded.value.weapons[definition_id]
		var weapon: Dictionary = base.weapons[templates[binding.mode]].duplicate(true)
		weapon.projectile.erase("resource")
		weapon.projectile.merge(binding.projectile, true)
		result.weapons[definition_id] = weapon
	return result


## 按需读取已有荣耀素材包，保留每帧原点并缓存为共享 SpriteFrames。
## [param asset_reference] 由本地表现目录提供的 ALE 引用，不能来自网络消息。
## 返回带原点元数据的动画；资源缺失时返回 null。
static func load_ale(asset_reference: String) -> SpriteFrames:
	if _cache.has(asset_reference):
		return _cache[asset_reference]
	if _repository == null:
		if not bool(RuntimeContentBootstrap.mount_default().get("ok", false)):
			return null
		_repository = AleSpriteRepository.new()
		if not _repository.load_default():
			_repository = null
			return null
	var animation := _repository.load_animation(asset_reference)
	var source_frames: Array = animation.get("frames", [])
	if source_frames.is_empty():
		return null
	var frames := SpriteFrames.new()
	frames.add_animation(&"raw")
	frames.set_animation_speed(&"raw", 10.0)
	var origins: Array[Vector2] = []
	for frame: Dictionary in source_frames:
		frames.add_frame(&"raw", frame["texture"])
		origins.append(frame["origin"])
	frames.set_meta("ale_origins", origins)
	_cache[asset_reference] = frames
	return frames


## 从实际装备的世界表现构建八向或共享动作，不回退为上一件装备。
## [param equipment] 当前装配物品。
## 返回包含动作和方向信息的组件；没有可用世界素材时返回空字典。
## 设计：战车底盘遵循原版 multisrc 八方向分组，尾部附图不属于移动动作，不能因总帧数不整除8而改为单向循环。
static func equipment_component(equipment: VehicleEquipment) -> Dictionary:
	if equipment == null:
		return {}
	var world := equipment.presentation_for("world")
	var action := _equipment_action(String(world.get("ale_reference", "")), equipment is VehicleChassis)
	if action.is_empty():
		return {}
	var component := {"action": action}
	var idle_reference := String(world.get("idle_ale_reference", ""))
	if not idle_reference.is_empty():
		var idle := _equipment_action(idle_reference, equipment is VehicleChassis)
		if idle.is_empty():
			return {}
		idle["fps"] = float(world.get("idle_fps", 10.0))
		component["idle_action"] = idle
	return component


## 从单个世界素材构造动作，每种动作按自身帧数独立分组。
## [param asset_reference] 本地表现目录指定的荣耀 ALE 引用。
## [param require_eight_way] 底盘必须使用八方向，其他装备保留原有共享动作兼容。
## 返回动作定义；缺失或不足一个完整方向组时返回空字典。
static func _equipment_action(asset_reference: String, require_eight_way: bool) -> Dictionary:
	if asset_reference.is_empty():
		return {}
	var frames := load_ale(asset_reference)
	if frames == null:
		return {}
	var count := frames.get_frame_count(&"raw")
	var directional := require_eight_way or (count >= 8 and count % 8 == 0)
	if directional and count < 8:
		return {}
	return {"ale_reference": asset_reference,
		"direction_mode": "eight_way" if directional else "shared",
		"frames_per_direction": floori(float(count) / 8.0) if directional else count,
		"fps": 10.0, "loop": true, "offset": [0, 0]}
