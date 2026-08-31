class_name AuthoritativeAutosaveService
extends RefCounted


var interval_seconds := 3.0
var save_count := 0
var last_errors: Dictionary = {}

var _repository: PlayerStateRepository
var _elapsed_seconds := 0.0
var _states: Dictionary = {}


## 配置权威服务器使用的仓储与自动存档间隔。
## [param repository] 已完成初始化的玩家状态仓储。
## [param requested_interval_seconds] 两次自动提交之间的秒数，默认三秒。
## 返回该函数计算、查询或操作得到的结果。
## 设计：本服务只负责定时和聚合提交，不读取网络载荷，也不实现具体存储协议。
func configure(
	repository: PlayerStateRepository,
	requested_interval_seconds: float = 3.0,
) -> DomainResult:
	if repository == null or requested_interval_seconds <= 0.0:
		return DomainResult.failure(&"persistence.invalid_autosave_config", "autosave repository and interval are required")
	_repository = repository
	interval_seconds = requested_interval_seconds
	_elapsed_seconds = 0.0
	save_count = 0
	last_errors.clear()
	_states.clear()
	return DomainResult.ok(self)


## 登记玩家聚合；仓储已有记录时优先采用已提交版本。
## [param initial_state] 新角色首次落盘所需的完整合法聚合。
## 返回该函数计算、查询或操作得到的结果。
func register_player(initial_state: PlayerStateRecord) -> DomainResult:
	if _repository == null or initial_state == null:
		return DomainResult.failure(&"persistence.autosave_not_configured", "autosave service is not configured")
	var loaded := _repository.load_player(initial_state.character_id)
	if loaded.is_ok:
		_states[initial_state.character_id] = loaded.value
		return DomainResult.ok((loaded.value as PlayerStateRecord).duplicate_record())
	if loaded.error_code != &"persistence.character_not_found":
		return loaded
	var created := _repository.create_player(initial_state)
	if created.is_ok:
		_states[initial_state.character_id] = created.value
	return created


## 推进服务器计时，并在达到间隔后提交所有已登记角色。
## [param elapsed_seconds] 本次服务器循环推进的秒数。
## [param state_collector] 从服务器会话和地图实例采集最新聚合的回调。
## 返回该函数计算、查询或操作得到的结果。
func advance(elapsed_seconds: float, state_collector: Callable) -> DomainResult:
	if elapsed_seconds <= 0.0:
		return DomainResult.ok(false)
	_elapsed_seconds += elapsed_seconds
	if _elapsed_seconds + 0.000001 < interval_seconds:
		return DomainResult.ok(false)
	_elapsed_seconds = fmod(_elapsed_seconds, interval_seconds)
	var saved := save_all(state_collector)
	return DomainResult.ok(true) if saved.is_ok else saved


## 立即保存全部已登记角色，任一失败时返回首个错误。
## [param state_collector] 从权威运行时采集每个角色最新聚合的回调。
## 返回该函数计算、查询或操作得到的结果。
func save_all(state_collector: Callable) -> DomainResult:
	if _repository == null or not state_collector.is_valid():
		return DomainResult.failure(&"persistence.invalid_autosave_collector", "autosave collector is invalid")
	var character_ids := _states.keys()
	character_ids.sort()
	var committed_count := 0
	for character_id: String in character_ids:
		var result := save_player(character_id, state_collector)
		if not result.is_ok:
			return result
		committed_count += 1
	return DomainResult.ok(committed_count)


## 立即采集并乐观提交指定角色的一份完整聚合。
## [param character_id] 已登记角色的稳定标识。
## [param state_collector] 从权威运行时采集该角色最新聚合的回调。
## 返回该函数计算、查询或操作得到的结果。
func save_player(character_id: String, state_collector: Callable) -> DomainResult:
	if not _states.has(character_id) or not state_collector.is_valid():
		return DomainResult.failure(&"persistence.autosave_character_unknown", "autosave character is not registered")
	var current: PlayerStateRecord = _states[character_id]
	var collected: Variant = state_collector.call(current.duplicate_record())
	if not collected is DomainResult:
		return DomainResult.failure(&"persistence.invalid_autosave_collector", "autosave collector must return DomainResult")
	if not collected.is_ok:
		last_errors[character_id] = collected.error_code
		return collected
	var candidate: PlayerStateRecord = collected.value
	var committed := _repository.save_player(candidate, current.revision)
	if not committed.is_ok:
		last_errors[character_id] = committed.error_code
		return committed
	_states[character_id] = committed.value
	last_errors.erase(character_id)
	save_count += 1
	return DomainResult.ok((committed.value as PlayerStateRecord).duplicate_record())


## 原子提交面板事务生成的完整玩家聚合，并刷新自动存档内存副本。
## [param character_id] 已登记角色标识。
## [param candidate] 已由权威领域服务校验的候选聚合。
## 返回仓储提交后的新 revision 聚合或冲突错误。
## 设计：装备事务同时修改背包和装配，必须通过一次仓储提交保持两份快照一致。
func commit_player_state(character_id: String, candidate: PlayerStateRecord) -> DomainResult:
	if _repository == null or not _states.has(character_id) or candidate == null \
			or candidate.character_id != character_id:
		return DomainResult.failure(&"persistence.autosave_character_unknown", "autosave character is not registered")
	var current: PlayerStateRecord = _states[character_id]
	var committed := _repository.save_player(candidate, current.revision)
	if not committed.is_ok:
		last_errors[character_id] = committed.error_code
		return committed
	_states[character_id] = committed.value
	last_errors.erase(character_id)
	save_count += 1
	return DomainResult.ok((committed.value as PlayerStateRecord).duplicate_record())


## 替换尚待下一次自动存档提交的权威内存聚合。
## [param character_id] 已登记角色标识。
## [param candidate] 已由领域服务校验、但尚不需要立即落盘的候选聚合。
## 返回隔离后的内存副本或身份、格式错误。
## 设计：频繁的经验小数累计先进入自动存档内存；技能升级仍调用 commit_player_state 立即持久化。
func update_runtime_state(character_id: String, candidate: PlayerStateRecord) -> DomainResult:
	if not _states.has(character_id) or candidate == null \
			or candidate.character_id != character_id:
		return DomainResult.failure(&"persistence.autosave_character_unknown", "autosave character is not registered")
	var validation := candidate.validate()
	if not validation.is_ok:
		return validation
	var current: PlayerStateRecord = _states[character_id]
	candidate.revision = current.revision
	_states[character_id] = candidate.duplicate_record()
	return DomainResult.ok(candidate.duplicate_record())


## 移除角色的内存登记，但保留仓储中最后一次提交的记录。
## [param character_id] 不再参与自动存档的角色标识。
func unregister_player(character_id: String) -> void:
	_states.erase(character_id)
	last_errors.erase(character_id)


## 查询自动存档服务持有的隔离聚合副本。
## [param character_id] 待查询的已登记角色标识。
## 返回该函数计算、查询或操作得到的结果。
func state_for(character_id: String) -> PlayerStateRecord:
	var state := _states.get(character_id) as PlayerStateRecord
	return state.duplicate_record() if state != null else null
