class_name AiDemoProvider
extends AiDecisionProvider

var _generation := 0
var _random := RandomNumberGenerator.new()


## 提供不联网的演示行为，用于验证开关和共存，不冒充大模型推理。
## [param request_id] 请求号。[param observation] 自身观察。[param context] 目标和记忆。
func decide(request_id: int, observation: Dictionary, context: Dictionary) -> void:
	var generation := _generation
	var action := {"kind": "wait"}
	var targets: Dictionary = observation.get("targets", {})
	if observation.combat_active and observation.health < observation.max_health * 0.3:
		action = {"kind": "return_base"}
	else:
		for kind: String in ["pickup", "harvest", "hunt"]:
			for target: Dictionary in targets.get(kind, []):
				if not target.available: continue
				if kind == "hunt" and target.health > observation.max_health: continue
				action = {"kind": kind, "target_id": target.id}
				break
			if action.kind != "wait": break
	if action.kind == "wait":
		var position: Array = observation.position
		_random.seed = hash("%s:%d" % [context.get("actor", ""), request_id])
		action = {"kind": "move", "x": position[0] + _random.randf_range(-200, 200), "y": position[1] + _random.randf_range(-150, 150)}
	_deliver.call_deferred(generation, request_id, AiPlayerAction.parse(action))


## 撤销已排队的演示结果。
func cancel() -> void:
	_generation += 1


## 仅发布当前生命周期的结果。
## [param generation] 请求代次。[param request_id] 请求号。[param result] 解析结果。
func _deliver(generation: int, request_id: int, result: DomainResult) -> void:
	if generation == _generation: completed.emit(request_id, result)
