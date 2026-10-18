class_name AiPlayerExecutor
extends RefCounted

var _world: AiWorldPort


## 仅依赖窄端口，行动执行不认识场景或服务器内部服务。
## [param world] 权威世界端口。
func _init(world: AiWorldPort) -> void:
	_world = world


## 开始有限时长的行动，保存观察时地图，避免迟到决策跨图执行。
## [param actor] 角色。[param action] 合法行动。[param observation] 决策时观察。[param now] 单调毫秒。
func begin(actor: AiPlayerActor, action: AiPlayerAction, observation: AiPlayerObservation, now: int) -> void:
	actor.action = action
	actor.action_map = observation.map_id
	actor.action_deadline = now + 30000
	actor.action_performed = false
	actor.next_step = now
	actor.last_move_target = Vector2.INF
	actor.memory = action.memory


## 分步接近并执行行动，每次调用最多一次移动或事务，空结果代表尚在进行。
## [param actor] 执行角色。[param view] 当前观察。[param now] 单调毫秒。
## 返回终态结果或空值。
func step(actor: AiPlayerActor, view: AiPlayerObservation, now: int) -> DomainResult:
	if actor.action == null or now < actor.next_step: return null
	actor.next_step = now + 500
	if view.map_id != actor.action_map: return DomainResult.failure(&"ai.map_changed", "地图已变化，请重新决策")
	if now >= actor.action_deadline:
		return DomainResult.ok() if actor.action_performed else DomainResult.failure(&"ai.action_timeout", "行动超时")
	var action := actor.action
	if action.kind == "hunt" and view.health < view.max_health * 0.25:
		return DomainResult.failure(&"ai.health_low", "生命过低，中断狩猎等待撤退决策")
	if action.kind == "wait": return DomainResult.ok()
	if action.kind in ["panel", "self_repair", "return_base"]: return _world.perform(actor, action, null)
	var target := view.find(action.kind, action.target_id)
	var position := action.position
	var radius := 24.0
	if action.kind != "move":
		if target == null or not target.available:
			return DomainResult.ok() if action.kind == "hunt" and actor.action_performed else DomainResult.failure(&"ai.target_lost", "目标已消失或不可用")
		position = target.position
		radius = {"travel": 48.0, "hunt": 100.0, "mine": 55.0, "harvest": 100.0, "pickup": 90.0}.get(action.kind, 24.0)
		if action.kind == "hunt":
			var weapons: Dictionary = view.own_state.get("combat", {}).get("local_weapon_flight", {})
			if not weapons.has(action.ability_id): return DomainResult.failure(&"ai.weapon_missing", "未装备该武器")
			radius = maxf(24, float(weapons[action.ability_id].range) * 0.75)
	if view.position.distance_to(position) > radius:
		var direction := (view.position - position).normalized()
		var destination := position if action.kind == "move" else position + direction * radius * 0.8
		if not view.moving or actor.last_move_target.distance_to(destination) > 40:
			actor.last_move_target = destination
			var moved := _world.move(actor, destination)
			if not moved.is_ok: return moved
		return null
	if action.kind == "move": return DomainResult.ok()
	# 接近完成后先停止路径，避免采矿/采摘时仍向目标内部移动。
	if view.moving:
		var stopped := _world.move(actor, view.position)
		return null if stopped.is_ok else stopped
	var performed := _world.perform(actor, action, target)
	if action.kind == "hunt":
		if performed.is_ok:
			actor.action_performed = true
			return null
		if performed.error_code == &"combat.weapon_cooldown": return null
	return performed
