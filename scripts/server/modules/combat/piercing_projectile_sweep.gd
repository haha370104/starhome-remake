class_name PiercingProjectileSweep
extends RefCounted


## 扫掠当前弹段所有交点，以每发已命中身份集合阻止跨帧重复伤害。
## [param projectile] 本发权威弹体。[param previous] 上刻位置。[param next] 当前位置。
## [param collision_query] 接受地图、起点、终点与排除身份的首碰查询。[param settle_hit] 共用伤害回调。
## 返回弹体是否已经到达射程终点，途中命中不会结束飞行。
static func advance(projectile: Dictionary, previous: Vector2, next: Vector2, collision_query: Callable, settle_hit: Callable) -> bool:
	var hit_ids: PackedStringArray = projectile.get("hit_ids", PackedStringArray())
	while true:
		var collision: Dictionary = collision_query.call(String(projectile.map_instance_id), previous, next, hit_ids)
		if not bool(collision.get("hit", false)): break
		var id := String(collision.get("target_entity_id", ""))
		if id.is_empty() or id in hit_ids: break
		hit_ids.append(id)
		var contact := projectile.duplicate(false)
		contact.target_entity_id = id
		contact.impact_position = collision.position
		contact.projectile_continues = true
		settle_hit.call(contact)
	projectile.hit_ids = hit_ids
	projectile.position = next
	projectile.target_entity_id = ""
	projectile.impact_position = projectile.endpoint
	return next.is_equal_approx(projectile.endpoint)
