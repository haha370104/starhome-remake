class_name CommerceRecordAdapter
extends RefCounted

## 测试专用桥接：把旧测试使用的存档 DTO 转为当前权威 Player 聚合。
## 运行时代码不接受 PlayerStateRecord；这里仅减少历史测试夹具的重复迁移代码。
static func execute(service: AuthoritativeCommerceService, state: Variant, command: Dictionary) -> DomainResult:
	if state is Player:
		return service.execute(state, command)
	if not state is PlayerStateRecord:
		return DomainResult.failure(&"test.invalid_state", "commerce test state must be Player or PlayerStateRecord")
	var mapper := PlayerStateMapper.new(service._catalog)
	var player_result := mapper.to_domain(state)
	if not player_result.is_ok:
		return player_result
	var result := service.execute(player_result.value, command)
	if not result.is_ok or not result.value is Dictionary or not result.value.has("candidate"):
		return result
	var value: Dictionary = result.value.duplicate(true)
	var candidate := mapper.to_record(result.value.candidate)
	if not candidate.is_ok:
		return candidate
	value["candidate"] = candidate.value
	return DomainResult.ok(value)


## 从存档 DTO 构造当前 Player 的面板快照。
static func build_bundle(service: AuthoritativeCommerceService, state: Variant, operation: Dictionary = {}) -> Dictionary:
	if state is Player:
		return service.build_bundle(state, operation)
	if not state is PlayerStateRecord:
		return {}
	var mapper := PlayerStateMapper.new(service._catalog)
	var player_result := mapper.to_domain(state)
	if not player_result.is_ok:
		return {}
	return service.build_bundle(player_result.value, operation)
