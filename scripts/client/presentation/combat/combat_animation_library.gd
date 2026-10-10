class_name CombatAnimationLibrary
extends RefCounted

## 把离线核对的武器弹体关联追加到既有表现清单，不改变权威伤害规则。
## [param base] 已导入的新手弹道、烟雾和爆炸模板。
## 返回含全部可用武器弹体的隔离清单。
static func with_weapon_bindings(base: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	var weapons: Dictionary = result.get("weapons", {})
	_ensure_secondary_weapon_templates(weapons)
	result["weapons"] = weapons
	var loaded := JsonConfigLoader.load_dictionary("res://data/presentation/weapon_visual_bindings_v1.json")
	if not loaded.is_ok:
		return result
	var templates := {"energy_cannon": "recruit_energy_cannon", "missile": "starter_missile", "rocket_launcher": "starter_rocket_launcher"}
	for definition_id: String in loaded.value.weapons:
		var binding: Dictionary = loaded.value.weapons[definition_id]
		var template_id: String = templates.get(String(binding.mode), "")
		if template_id.is_empty() or not weapons.has(template_id):
			continue
		var weapon: Dictionary = weapons[template_id].duplicate(true)
		weapon.projectile.erase("resource")
		weapon.projectile.merge(binding.projectile, true)
		weapons[definition_id] = weapon
	return result


## 为基础清单补上已导入的初始副武器模板。
## 这些模板属于客户端公共表现资源；跨版本绑定只覆盖弹体引用，不改变基础爆炸资源。
static func _ensure_secondary_weapon_templates(weapons: Dictionary) -> void:
	if not weapons.has("starter_missile"):
		weapons["starter_missile"] = {
			"owner_actor_id": "starter_combat_vehicle",
			"maximum_visual_range": 400.0,
			"minimum_visual_range": 0.0,
			"cooldown_seconds": 2.0,
			"muzzle_offset": [0.0, -16.0],
			"projectile": {
				"resource": "res://assets/equipment_world/starter_secondary_weapons/missile/projectile/flight/animation_frames.tres",
				"frames": 1, "fps": 10.0, "loop": true,
				"travel_pixels_per_second": 250.0,
			},
			"impact": {
				"resource": "res://assets/equipment_world/starter_secondary_weapons/missile/impact/explosion/animation_frames.tres",
				"frames": 6, "fps": 12.0, "loop": false,
			},
		}
	if not weapons.has("starter_rocket_launcher"):
		weapons["starter_rocket_launcher"] = {
			"owner_actor_id": "starter_combat_vehicle",
			"maximum_visual_range": 350.0,
			"minimum_visual_range": 150.0,
			"cooldown_seconds": 3.0,
			"muzzle_offset": [0.0, -16.0],
			"muzzle": {
				"resource": "res://assets/equipment_world/starter_secondary_weapons/rocket/impact/smoke/animation_frames.tres",
				"frames": 6, "fps": 12.0, "loop": false,
			},
			"projectile": {
				"resource": "res://assets/equipment_world/starter_secondary_weapons/rocket/projectile/flight/animation_frames.tres",
				"frames": 4, "fps": 10.0, "loop": true,
				"travel_pixels_per_second": 1000.0,
			},
			"impact": {
				"resource": "res://assets/equipment_world/starter_secondary_weapons/rocket/impact/explosion/animation_frames.tres",
				"frames": 8, "fps": 12.0, "loop": false,
			},
		}


## 按需读取已有荣耀素材包，保留每帧原点并缓存为共享 SpriteFrames。
## [param asset_reference] 由本地表现目录提供的 ALE 引用，不能来自网络消息。
## 返回带原点元数据的动画；资源缺失时返回 null。
static func load_ale(asset_reference: String) -> SpriteFrames:
	var repository := SpriteResources.repository()
	if repository == null:
		return null
	return repository.load_sprite_frames(asset_reference)


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
