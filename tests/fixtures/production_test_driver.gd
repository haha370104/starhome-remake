class_name ProductionTestDriver
extends RefCounted


## 为配方专项先发送真实开始命令，再模拟服务端到期；不提供运行时代码的即时后门。
## [param service] 权威生产服务。[param catalog] 物品目录。[param state] 隔离测试记录。
## [param command] 保留配方、库存版本与干扰字段的测试意图。
## 返回已完成的一轮候选；实际时钟、写盘和断线由独立真实服务器测试覆盖。
static func execute(service: RefCounted, catalog: ItemCatalog, state: PlayerStateRecord, command: Dictionary, rewards: RewardPipeline = null) -> DomainResult:
	var mapper := PlayerStateMapper.new(catalog, rewards)
	var mapped := mapper.to_domain(state)
	if not mapped.is_ok: return mapped
	var player: Player = mapped.value
	var intent := command
	var starts_production := String(command.get("type", "")) == "start_production"
	if starts_production:
		intent = command.duplicate(true)
		intent.merge({"cycles": 1, "speed": 1, "production_revision": player.production.revision}, false)
	var result: DomainResult = service.execute(player, intent)
	if not result.is_ok: return result
	if starts_production:
		var pending: Player = result.value.candidate
		var order := pending.production.order
		pending.production.capture_remaining(order.id, pending.production.revision, 0)
		result = service.complete_production_cycle(pending)
		if not result.is_ok: return result
	var candidate: Player = result.value.candidate
	if starts_production:
		result.value["panel_bundle"] = service.build_bundle(candidate, result.value.operation)
	var recorded := mapper.to_record(candidate)
	if not recorded.is_ok: return recorded
	result.value["candidate"] = recorded.value
	return result
