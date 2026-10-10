class_name AuthoritativeAutosaveService
extends RefCounted

const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")
const DIRTY_DOMAINS := [
	"character", "inventory", "warehouse", "vehicle", "skills", "quests", "achievements",
	"daily", "food", "production", "central", "presets", "location", "social",
]

var interval_seconds := 3.0
var save_count := 0
var last_errors: Dictionary = {}
var last_capture_domain_bytes: Dictionary = {}
var players := OnlinePlayerStore.new()
var mapper: PlayerStateMapper
var _repository: PlayerStateRepository
var _elapsed_seconds := 0.0
var _saved_revisions: Dictionary[String, int] = {}
var _saved_records: Dictionary[String, PlayerStateRecord] = {}
var _dirty_domains: Dictionary[String, Dictionary] = {}


## 配置持久化端口；在线状态由独立的玩家所有者持有。
## [param repository] 已初始化仓储。[param requested_interval_seconds] 原有检查点周期。
## 返回初始化结果。
func configure(repository: PlayerStateRepository, requested_interval_seconds: float = 3.0) -> DomainResult:
	if repository == null or requested_interval_seconds <= 0:
		return DomainResult.failure(&"persistence.autosave_not_configured", "repository and interval are required")
	_repository = repository
	interval_seconds = requested_interval_seconds
	_elapsed_seconds = 0.0
	_saved_revisions.clear()
	_saved_records.clear()
	_dirty_domains.clear()
	last_capture_domain_bytes.clear()
	last_errors.clear()
	players = OnlinePlayerStore.new()
	return DomainResult.ok(self)


## 在载入边界还原一次领域对象，保存版本独立于在线事务版本。
## [param initial_state] 首次创建时使用的初始记录。
## 返回唯一在线玩家或载入错误。
func register_player(initial_state: PlayerStateRecord) -> DomainResult:
	var existing := players.player_for(initial_state.character_id)
	if existing != null: return DomainResult.ok(existing)
	var loaded := _repository.load_player(initial_state.character_id)
	var created := false
	if not loaded.is_ok and loaded.error_code == &"persistence.character_not_found":
		loaded = _repository.create_player(initial_state)
		created = loaded.is_ok
	if not loaded.is_ok: return loaded
	var restored := mapper.to_domain(loaded.value)
	if not restored.is_ok: return restored
	_saved_revisions[initial_state.character_id] = loaded.value.revision
	_saved_records[initial_state.character_id] = loaded.value
	if created: mark_dirty(initial_state.character_id)
	return DomainResult.ok(players.register(restored.value))


## 按既有检查点周期生成隔离快照，后台线程不接触在线对象。
## [param elapsed_seconds] 模拟经过秒数。[param collector] 采集地图和战斗即时状态。
## [param defer_if_due] 本帧有重型世界刷新时暂缓一个模拟帧，保留到期计时。
## 返回是否保存或具体失败；失败不会移除在线待保存状态。
func advance(elapsed_seconds: float, collector: Callable, defer_if_due := false) -> DomainResult:
	if elapsed_seconds <= 0: return DomainResult.ok(false)
	_elapsed_seconds += elapsed_seconds
	if _elapsed_seconds + 0.000001 < interval_seconds: return DomainResult.ok(false)
	if defer_if_due:
		return DomainResult.ok(false)
	_elapsed_seconds = fmod(_elapsed_seconds, interval_seconds)
	var checkpoint_status := _repository.checkpoint_status()
	if not checkpoint_status.is_ok:
		_repository.ground_dirty = true
		for identity: String in players.identities(): mark_dirty(identity)
	var saved := save_dirty(collector)
	if not saved.is_ok: return saved
	if int(saved.value) == 0 and not _repository.ground_dirty: return checkpoint_status if not checkpoint_status.is_ok else DomainResult.ok(true)
	var queued := _repository.queue_checkpoint()
	if not queued.is_ok:
		for identity: String in players.identities(): mark_dirty(identity)
	return DomainResult.ok(true) if queued.is_ok else queued


## 保存所有在线角色，保留首次失败供正常退出报告。
## [param collector] 同步采集各状态所有者的最新事实。
## 返回保存数量或失败。
func save_all(collector: Callable) -> DomainResult:
	var count := 0
	for identity: String in players.identities():
		var saved := save_player(identity, collector)
		if not saved.is_ok: return saved
		count += 1
	return DomainResult.ok(count)


## 只捕获本检查点前发生过变化的在线角色；未变化角色不重做领域映射。
## [param collector] 同步采集地图和战斗即时状态。
## 返回实际捕获数量或首个失败。
func save_dirty(collector: Callable) -> DomainResult:
	var count := 0
	for identity: String in _dirty_identities():
		var saved := save_player(identity, collector)
		if not saved.is_ok: return saved
		count += 1
	return DomainResult.ok(count)


## 捕获当前状态并在保存边界转换，保存成功不反向替换在线聚合。
## [param identity] 在线角色。[param collector] 同步状态采集器。
## 返回保存记录或失败。
func save_player(identity: String, collector: Callable) -> DomainResult:
	var player := players.player_for(identity)
	if player == null or not collector.is_valid():
		return DomainResult.failure(&"persistence.autosave_character_unknown", "player or collector unavailable")
	var domains := dirty_domains_for(identity)
	if domains.is_empty(): domains = _all_dirty_domains()
	var copied_started_at := PerformanceTelemetryScript.begin(&"autosave_capture_copy")
	var base: PlayerStateRecord = _saved_records.get(identity)
	if base == null:
		var initial := mapper.to_record(player)
		if not initial.is_ok: return initial
		base = initial.value
	var copied := mapper.merge_domains(base, player, domains)
	PerformanceTelemetryScript.end(&"autosave_capture_copy", copied_started_at)
	if not copied.is_ok: return copied
	var capture_started_at := PerformanceTelemetryScript.begin(&"autosave_capture")
	var captured: DomainResult = collector.call(copied.value, domains)
	PerformanceTelemetryScript.end(&"autosave_capture", capture_started_at)
	return _save_record(captured.value, identity, false, domains) if captured.is_ok else captured


## 提交玩法候选；正常退出先持久化成功，再发布在线状态。
## [param identity] 权威角色。[param candidate] 同版本候选。[param durable] 是否等待落盘。
## 返回在线聚合或失败。
func commit_player(
	identity: String,
	candidate: Player,
	durable := false,
	ground_transfer: Dictionary = {},
	domains: Array[String] = [],
) -> DomainResult:
	var current := players.player_for(identity)
	if current == null or candidate == null or candidate.entity_id != identity or candidate.revision != current.revision:
		return DomainResult.failure(&"player.stale", "online transaction is stale")
	if durable or not ground_transfer.is_empty():
		var all_domains := _all_dirty_domains()
		var saved := _save(candidate, durable, all_domains, ground_transfer)
		if not saved.is_ok: return saved
	var committed := players.commit(identity, candidate)
	if committed.is_ok and not durable: mark_dirty(identity, domains)
	return committed


## 查询在线聚合，不生成存档副本；修改必须由领域事务完成。
## [param identity] 权威角色。
## 返回在线对象或空值。
func commit_players_atomic(
	candidates: Dictionary,
	domains: Array[String],
	additional_records: Dictionary = {},
	additional_expected_revisions: Dictionary = {},
) -> DomainResult:
	if candidates.is_empty() or mapper == null or domains.is_empty() \
			or additional_records.size() != additional_expected_revisions.size():
		return DomainResult.failure(&"persistence.invalid_transaction", "atomic player commit inputs are invalid")
	var records: Dictionary = {}
	var expected_revisions: Dictionary = {}
	for raw_identity: Variant in candidates:
		var identity := String(raw_identity)
		var current := players.player_for(identity)
		var candidate: Variant = candidates[raw_identity]
		var base: PlayerStateRecord = _saved_records.get(identity)
		if current == null or not candidate is Player or candidate.entity_id != identity \
				or candidate.revision != current.revision or base == null \
				or not _saved_revisions.has(identity):
			return DomainResult.failure(&"player.stale", "a player changed before the atomic commit")
		var merged: DomainResult = mapper.merge_domains(base.duplicate_record(), candidate, domains + dirty_domains_for(identity))
		if not merged.is_ok: return merged
		var validation: DomainResult = merged.value.validate()
		if not validation.is_ok: return validation
		records[identity] = merged.value
		expected_revisions[identity] = _saved_revisions[identity]
	for raw_identity: Variant in additional_records:
		if not raw_identity is String or records.has(raw_identity) \
				or not additional_expected_revisions.has(raw_identity):
			return DomainResult.failure(&"persistence.invalid_transaction", "additional atomic records are invalid")
		var identity := String(raw_identity)
		var record: Variant = additional_records[raw_identity]
		var expected_value: Variant = additional_expected_revisions[raw_identity]
		if not record is PlayerStateRecord or record.character_id != identity \
				or not expected_value is int or record.revision != int(expected_value):
			return DomainResult.failure(&"persistence.invalid_transaction", "additional atomic record is invalid")
		var validation: DomainResult = record.validate()
		if not validation.is_ok: return validation
		records[identity] = record
		expected_revisions[identity] = int(expected_value)
	var saved := _repository.save_players_atomic_durable(records, expected_revisions)
	if not saved.is_ok: return saved
	var persisted_records: Variant = saved.value
	if not persisted_records is Dictionary or persisted_records.size() != records.size():
		return DomainResult.failure(&"persistence.invalid_transaction", "atomic repository result is incomplete")
	for identity: String in records:
		var persisted: Variant = persisted_records.get(identity)
		if not persisted is PlayerStateRecord or persisted.character_id != identity \
				or persisted.revision != int(expected_revisions[identity]) + 1:
			return DomainResult.failure(&"persistence.invalid_transaction", "atomic repository result is invalid")
	var committed := players.commit_many(candidates)
	if not committed.is_ok: return committed
	for identity: String in candidates:
		var saved_record: PlayerStateRecord = persisted_records[identity]
		_saved_revisions[identity] = saved_record.revision
		_saved_records[identity] = saved_record
		var dirty: Dictionary = _dirty_domains.get(identity, {})
		for domain: String in domains: dirty.erase(domain)
		if dirty.is_empty(): _dirty_domains.erase(identity)
		else: _dirty_domains[identity] = dirty
		last_errors.erase(identity)
		save_count += 1
	_update_dirty_gauge()
	return committed


func player_for(identity: String) -> Player:
	return players.player_for(identity)


## 已结算的内部变化通过相同所有者提交，不维护第二份状态。
## [param identity] 权威角色。[param candidate] 内部用例候选。
## 返回提交结果。
func update_runtime_state(identity: String, candidate: Player, domains: Array[String] = []) -> DomainResult:
	var committed := players.commit(identity, candidate)
	if committed.is_ok: mark_dirty(identity, domains)
	return committed


## 释放结束会话的内存状态，已保存记录继续由仓储拥有。
## [param identity] 结束的角色。
func unregister_player(identity: String) -> void:
	players.remove(identity)
	_saved_revisions.erase(identity)
	_saved_records.erase(identity)
	_dirty_domains.erase(identity)
	_update_dirty_gauge()
	last_errors.erase(identity)


## 高频成长仅隔离技能组件，成功后合入同一在线玩家。
## [param identity] 在线角色。[param operation] 技能领域用例。
## 返回成长结果或失败。
func apply_skill_progression(identity: String, operation: Callable) -> DomainResult:
	var player := player_for(identity)
	if player == null or not operation.is_valid():
		return DomainResult.failure(&"player.missing", "online player unavailable")
	var candidate := PlayerSkillProgression.new(SkillBook.new(player.skills.to_dictionary()), player.level,
		player.account_id, player.food_status)
	var result: DomainResult = operation.call(candidate)
	if not result.is_ok: return result
	player.skills = candidate.skills
	player.level = candidate.level
	# 经验的小数部分仍只保留在在线聚合；达到新的可见百分比时推进
	# 玩家 revision，使客户端能安全接收细粒度技能增量。驾驶经验也走这条路径，
	# 不再因为来源是高频移动而让客户端长期停留在旧显示值。
	var visible_change := bool(result.value.get("visible_progress_changed", false))
	if bool(result.value.get("upgraded", false)) or visible_change:
		var committed := players.commit(identity, player)
		if not committed.is_ok:
			return committed
		mark_dirty(identity, ["skills", "character"])
	return result


## 将隔离记录交给仓储，保存版本只在成功后推进。
## [param player] 当前完整领域状态。[param durable] 是否等待文件写入完成。
## 返回仓储记录或错误；不会把旧保存结果覆盖回在线玩家。
func _save(player: Player, durable: bool, domains: Array[String] = [], ground_transfer: Dictionary = {}) -> DomainResult:
	var serialize_started_at := PerformanceTelemetryScript.begin(&"autosave_serialize")
	var recorded := mapper.to_record(player)
	PerformanceTelemetryScript.end(&"autosave_serialize", serialize_started_at)
	if not recorded.is_ok: return recorded
	return _save_record(recorded.value, player.entity_id, durable, domains, ground_transfer)


## 将已经捕获的记录交给仓储；普通自动存档不再重新映射 Player。
func _save_record(
	record: PlayerStateRecord,
	identity: String,
	durable: bool,
	domains: Array[String] = [],
	ground_transfer: Dictionary = {},
) -> DomainResult:
	if record == null or identity.is_empty():
		return DomainResult.failure(&"persistence.autosave_record_missing", "captured record is unavailable")
	var captured_domains := domains if not domains.is_empty() else dirty_domains_for(identity)
	if captured_domains.is_empty(): captured_domains = _all_dirty_domains()
	_record_domain_sizes(record, captured_domains)
	var expected := _saved_revisions[identity]
	var result := _repository.save_ground_transfer(record, expected, ground_transfer) if not ground_transfer.is_empty() \
		else _repository.save_player_durable(record, expected) if durable \
		else _repository.save_player(record, expected)
	if not result.is_ok:
		last_errors[identity] = result.error_code
		return result
	_saved_revisions[identity] = result.value.revision
	# Repository increments the persistence revision on its isolated candidate.
	# Keep the captured record as the next merge base without another deep copy.
	record.revision = result.value.revision
	_saved_records[identity] = record
	_dirty_domains.erase(identity)
	_update_dirty_gauge()
	last_errors.erase(identity)
	save_count += 1
	return result


## 标记角色的持久化领域；省略领域表示完整聚合发生变化。
## [param identity] 在线角色身份。[param domains] 发生变化的持久化领域。
func mark_dirty(identity: String, domains: Array[String] = []) -> void:
	if identity.is_empty(): return
	var dirty: Dictionary = _dirty_domains.get(identity, {})
	var selected := DIRTY_DOMAINS if domains.is_empty() else domains
	for domain: String in selected:
		if domain in DIRTY_DOMAINS: dirty[domain] = true
	_dirty_domains[identity] = dirty
	_update_dirty_gauge()


## 更新当前仍有待保存领域的角色数量。
func _update_dirty_gauge() -> void:
	PerformanceTelemetryScript.set_gauge(&"autosave_dirty_players", float(_dirty_domains.size()))


## 返回排序后的 dirty 领域，保证测试、报告和后续 checkpoint 行为确定。
## [param identity] 在线角色身份。
func dirty_domains_for(identity: String) -> Array[String]:
	var result: Array[String] = []
	for domain: String in (_dirty_domains.get(identity, {}) as Dictionary).keys(): result.append(domain)
	result.sort()
	return result


## 返回完整且明确类型化的领域列表，供退出和显式全量保存使用。
func _all_dirty_domains() -> Array[String]:
	var result: Array[String] = []
	for domain: String in DIRTY_DOMAINS: result.append(domain)
	return result


## 返回当前待捕获角色；未变化角色不进入映射和采集阶段。
func _dirty_identities() -> Array[String]:
	var result: Array[String] = []
	for identity: String in players.identities():
		if not dirty_domains_for(identity).is_empty(): result.append(identity)
	result.sort()
	return result


## 记录本次变更领域的冻结副本大小，避免只看完整存档大小掩盖热点领域。
## [param record] 已完成校验的玩家存档记录。[param domains] 本次 dirty 领域。
func _record_domain_sizes(record: PlayerStateRecord, domains: Array[String]) -> void:
	var sizes: Dictionary = {}
	var payloads := _domain_payloads(record)
	var total := 0
	for domain: String in domains:
		var bytes := JSON.stringify(payloads.get(domain, {})).to_utf8_buffer().size()
		sizes[domain] = bytes
		total += bytes
		PerformanceTelemetryScript.set_gauge(StringName("autosave_domain_bytes_%s" % domain), float(bytes))
	last_capture_domain_bytes = sizes
	PerformanceTelemetryScript.set_gauge(&"autosave_last_domain_bytes_total", float(total))
	PerformanceTelemetryScript.increment(&"autosave_dirty_domain_count", domains.size())


## 将持久化记录拆成报告用领域，不改变磁盘 schema 和实际写入格式。
func _domain_payloads(record: PlayerStateRecord) -> Dictionary:
	return {
		"character": {"level": record.character_level, "health": record.character_health,
			"experience": record.character_experience, "skills": record.character_skills,
			"quests": record.quest_states, "achievements": record.achievements},
		"inventory": {"revision": record.inventory_revision, "capacity": record.inventory_capacity,
			"currency": record.currency, "stacks": record.inventory_stacks.map(
				func(stack: InventoryStackRecord) -> Dictionary: return stack.to_dictionary())},
		"warehouse": record.warehouse.to_dictionary(),
		"vehicle": {"id": record.vehicle_id, "definition_id": record.vehicle_definition_id,
			"health": record.vehicle_health, "reserve_energy": record.reserve_energy,
			"working_energy": record.working_energy, "equipment": record.equipment_slots.map(
				func(slot: EquipmentSlotRecord) -> Dictionary: return slot.to_dictionary())},
		"skills": record.character_skills,
		"quests": record.quest_states,
		"achievements": record.achievements,
		"daily": record.daily_activities,
		"food": record.food_status,
		"production": record.production.to_dictionary(),
		"central": record.central.to_dictionary(),
		"presets": record.vehicle_presets.to_dictionary(),
		"location": {"map_id": record.map_id, "map_instance_id": record.map_instance_id,
			"position": [record.position.x, record.position.y], "facing_direction": record.facing_direction,
			"checkpoint_id": record.checkpoint_id},
		"social": {"friends": record.friend_ids, "enemies": record.enemy_ids, "mailbox": record.mailbox},
	}


## 查询仓储最后接受的保存版本，不能与在线事务版本混用。
## [param identity] 已登记角色。
## 返回仓储版本，不存在时为负一。
func saved_revision_for(identity: String) -> int:
	return _saved_revisions.get(identity, -1)
