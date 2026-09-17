class_name AuthoritativeCorrosionModule
extends RefCounted

const BODY_OFFSET := Vector2(0, -16)
var _clouds: Array[CorrosiveCloud] = []


## 接收服务端弹体结算，将同源效果合并或登记独立毒雾。
## [param cloud] 已完成身份与命中校验的领域腐蚀对象。
## [param tick] 当前逻辑时钟。
func add(cloud: CorrosiveCloud, tick: int) -> void:
	for current: CorrosiveCloud in _clouds:
		if current.can_refresh(cloud):
			current.refresh(tick)
			return
	_clouds.append(cloud)


## 推进毒雾领域时钟，并经战车领域对象结算伤害。
## [param tick] 当前权威时钟，不依赖客户端动画。
## [param actors] 战斗模块的旧版玩家适配边界；伤害仍由 VehicleCombatState 拥有。
## 返回需要发布的实际伤害事件。
func advance(tick: int, actors: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for index in range(_clouds.size() - 1, -1, -1):
		var cloud := _clouds[index]
		if not _attachment_valid(cloud, actors) or cloud.is_expired(tick):
			_clouds.remove_at(index)
			continue
		if cloud.consume_pulse(tick):
			for actor_id: String in actors:
				var actor: Dictionary = actors[actor_id]
				var vehicle: VehicleCombatState = actor.vehicle_state
				var center: Vector2 = actor.position + BODY_OFFSET
				if vehicle.health <= 0 or not cloud.affects(actor_id, String(actor.map_instance_id), center):
					continue
				var result := vehicle.apply_damage(cloud.damage_per_tick, true)
				events.append({"event_type": &"monster_attack_resolved", "server_tick": tick,
					"impact_tick": tick, "attack_id": "%s.pulse.%d.%s" % [cloud.effect_id, tick, actor_id],
					"attacker_id": cloud.attacker_id, "target_entity_id": actor_id,
					"attack_archetype": &"corrosive_projectile", "combat_actor_id": cloud.combat_actor_id,
					"corrosion_pulse": true, "impact_position": [center.x, center.y],
					"damage": int(result.value.applied_damage), "target_health": int(result.value.health),
					"target_destroyed": bool(result.value.destroyed)})
		if cloud.is_expired(tick) or not _attachment_valid(cloud, actors):
			_clouds.remove_at(index)
	return events


## 导出整份残留状态，允许新加入或丢失事件的客户端恢复表现。
## [param map_id] 快照接收者所在地图实例。
## [param actors] 服务端玩家适配记录，用于解析附着位置。
## 返回该地图全部有效残留 DTO。
func snapshots(map_id: String, actors: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cloud: CorrosiveCloud in _clouds:
		if cloud.map_instance_id != map_id or not _attachment_valid(cloud, actors):
			continue
		var point := cloud.position
		if not cloud.attached_actor_id.is_empty():
			point = actors[cloud.attached_actor_id].position + BODY_OFFSET
		result.append(cloud.snapshot(point))
	return result


## 查询残留是否全部结清，供空地图休眠判断。
## 返回没有活跃腐蚀对象时为 true。
func is_empty() -> bool:
	return _clouds.is_empty()


## 清空地图重置前的残留效果。
func clear() -> void:
	_clouds.clear()


## 玩家离图或注销时同步移除附着，防止复活后继承旧腐蚀。
## [param actor_id] 被移除的权威玩家身份。
func detach(actor_id: String) -> void:
	for index in range(_clouds.size() - 1, -1, -1):
		if _clouds[index].attached_actor_id == actor_id:
			_clouds.remove_at(index)


## 确认附着对象仍然存活并留在原地图，地面残留无需目标。
## [param cloud] 待校验的领域腐蚀对象。
## [param actors] 权威战车索引。
## 返回是否仍能推进和展示。
func _attachment_valid(cloud: CorrosiveCloud, actors: Dictionary) -> bool:
	if cloud.attached_actor_id.is_empty():
		return true
	if not actors.has(cloud.attached_actor_id):
		return false
	var actor: Dictionary = actors[cloud.attached_actor_id]
	return String(actor.map_instance_id) == cloud.map_instance_id \
		and (actor.vehicle_state as VehicleCombatState).health > 0
