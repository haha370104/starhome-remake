class_name ProductionTestDriver
extends RefCounted


## 为配方专项先发送真实开始命令，再模拟服务端到期；不提供运行时代码的即时后门。
## [param service] 权威生产服务。[param state] 隔离测试记录。
## [param command] 保留配方、库存版本与干扰字段的测试意图。
## 返回已完成的一轮候选；实际时钟、写盘和断线由独立真实服务器测试覆盖。
static func execute(service: RefCounted, state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	if String(command.get("type", "")) != "start_production": return service.execute(state, command)
	var intent := command.duplicate(true)
	intent.merge({"cycles": 1, "speed": 1, "production_revision": state.production.revision}, false)
	var started: DomainResult = service.execute(state, intent)
	if not started.is_ok: return started
	var candidate: PlayerStateRecord = started.value.candidate
	var order := candidate.production.order
	candidate.production.capture_remaining(order.id, candidate.production.revision, 0)
	var completed: DomainResult = service.complete_production_cycle(candidate)
	if completed.is_ok:
		completed.value["panel_bundle"] = service.build_bundle(completed.value.candidate, completed.value.operation)
	return completed
