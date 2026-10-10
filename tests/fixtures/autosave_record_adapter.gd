class_name AutosaveRecordAdapter
extends RefCounted

## 测试专用桥接：把在线 Player 映射成当前权威存档记录。
## 运行时代码只保留 Player 所有权，不恢复旧的 state_for API。
static func current(autosave: AuthoritativeAutosaveService, identity: String) -> PlayerStateRecord:
	var player: Player = autosave.player_for(identity)
	if player == null:
		return null
	var mapped: DomainResult = autosave.mapper.to_record(player)
	return mapped.value if mapped.is_ok else null


## 测试专用提交：将记录映射回在线 Player 后走正式提交入口。
static func commit(autosave: AuthoritativeAutosaveService, identity: String, record: PlayerStateRecord) -> DomainResult:
	var player_result: DomainResult = autosave.mapper.to_domain(record)
	if not player_result.is_ok:
		return player_result
	return autosave.commit_player(identity, player_result.value)
