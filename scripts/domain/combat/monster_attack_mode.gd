class_name MonsterAttackMode
extends RefCounted

var archetype: StringName
var base_attack: int
var attack_range: float
var interval_ticks: int
var projectile_speed: float
var projectile_hitbox_offset: Vector2
var projectile_hitbox_radius: float


## 初始化怪物近战或远程攻击模型。
## [param definition] 怪物配置中的攻击字段。
## [param simulation_hz] 权威服务器逻辑频率。
func _init(definition: Dictionary = {}, simulation_hz: int = 20) -> void:
	archetype = StringName(definition.get("attack_archetype", "contact_melee"))
	base_attack = maxi(0, int(definition.get("base_attack", 0)))
	attack_range = maxf(0.0, float(definition.get("attack_range", 0.0)))
	interval_ticks = maxi(1, roundi(
		float(definition.get("attack_interval_seconds", 1.5)) * maxi(1, simulation_hz)
	))
	var speed_value: Variant = definition.get("runtime_projectile_speed")
	projectile_speed = 0.0 if speed_value == null else maxf(0.0, float(speed_value))
	var hitbox: Variant = definition.get("projectile_hitbox", {})
	projectile_hitbox_offset = Vector2.ZERO
	projectile_hitbox_radius = 24.0
	if hitbox is Dictionary:
		var offset_value: Variant = hitbox.get("offset", [0.0, 0.0])
		if offset_value is Array and offset_value.size() == 2:
			projectile_hitbox_offset = Vector2(float(offset_value[0]), float(offset_value[1]))
		projectile_hitbox_radius = maxf(1.0, float(hitbox.get("radius", 24.0)))


## 判断攻击是否需要生成飞行弹体。
## 返回非贴身攻击且速度有效时为 true。
func is_projectile() -> bool:
	return archetype != &"contact_melee" and projectile_speed > 0.0
