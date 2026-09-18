extends SceneTree

class CountingMapper extends PlayerStateMapper:
	var calls := 0
	## 复用正式目录和倍率，仅记录是否重建了全量玩家。
	## [param catalog] 已初始化目录。[param rewards] 权威切面。
	func _init(catalog: ItemCatalog, rewards: RewardPipeline) -> void:
		super(catalog, rewards)
	## 监测实际映射调用，不改变还原行为。
	## [param record] 完整记录。
	## 返回实际还原结果。
	func to_domain(record: PlayerStateRecord) -> DomainResult:
		calls += 1
		return super(record)

class CountingRecord extends PlayerStateRecord:
	var serializations := 0
	## 检出完整存档复制重新进入每个驾驶tick的性能退化。
	## [param include_warehouse] 是否序列化仓库。
	## 返回实际完整序列化结果。
	func to_dictionary(include_warehouse: bool = true) -> Dictionary:
		serializations += 1
		return super(include_warehouse)

class RejectingRepository extends PlayerStateRepository:
	## 拒绝升级仓储提交，保留原版本。
	## [param _state] 候选。[param _expected_revision] 原版本。
	## 返回预期的写盘失败。
	func save_player(_state: PlayerStateRecord, _expected_revision: int) -> DomainResult:
		return DomainResult.failure(&"test.disk_failure", "预期的升级写盘失败")

var checks := 0
var failures := PackedStringArray()
var messages: Array[Dictionary] = []
var server := AuthoritativeServer.new()
var entity_id := ""


## 延迟执行真实服务器的高频成长与原子存档检查。
func _initialize() -> void:
	call_deferred("_run")


## 覆盖满级空操作、细粒度累计、倍率、失败回滚、重入、升级与重启保存。
func _run() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.player_state_store_path = "res://.godot/skill-progression-%d.json" % Time.get_ticks_usec()
	_check(server.initialize(config).ok, "server initializes")
	_check(server.open_session(2, {"protocol_version":config.protocol_version,"content_version":config.content_version},0).ok, "actual session")
	entity_id = server.sessions.session_for_peer(2).entity_id
	var service := server.player_panel_service
	var autosave := server.autosave_service
	var mapper := CountingMapper.new(service._catalog, server.reward_service.pipeline)
	service._mapper = mapper
	server.server_message_generated.connect(func(_peer: int, message: Dictionary) -> void: messages.append(message))
	var state := autosave.state_for(entity_id)
	state.character_skills.driving = {"level":1000,"current_exp":0,"fractional_exp":0.0}
	_check(autosave.commit_player_state(entity_id,state).is_ok, "test elevated skill saved")
	var spy := _install_counting_record()
	var before := spy.to_dictionary()
	spy.serializations = 0
	mapper.calls = 0
	var save_count := autosave.save_count
	var event := {"entity_id":entity_id,"source":"accepted_driving_movement","skill_id":"driving","distance":1.0,"vehicle_weight":1000.0,
		"account_id":"forged-account","multiplier":999,"now":0}
	for tick in 120: server._apply_skill_progression_event(event)
	_check(spy.serializations == 0 and mapper.calls == 0, "120 capped driving ticks never serialize full state or restore equipment")
	_check(messages.is_empty() and autosave.save_count == save_count, "capped movement emits no panels and causes no immediate write")
	_check(spy.to_dictionary() == before, "capped movement leaves every saved fact unchanged")
	state = autosave.state_for(entity_id)
	state.character_skills.driving = {"level":100,"current_exp":0,"fractional_exp":0.0}
	var now := int(Time.get_unix_time_from_system())
	state.food_status = {"physical":73,"cooldowns":{},"active":[FoodEffect.new({"kind":FoodEffect.SKILLS.find("driving"),"amount":20,"duration":600,"expires_at":now+600}).to_dictionary()]}
	_check(autosave.commit_player_state(entity_id,state).is_ok, "ordinary skill and food fixture")
	var rules: Array[RewardModifier] = [RewardModifier.parse({"id":"test.driving.vip","channel":"experience","multiplier":2.5,"account_ids":[state.account_id],"skill_ids":["driving"]}).value]
	server.reward_service.pipeline.add_provider(RewardModifierProvider.new(rules))
	spy = _install_counting_record()
	before = spy.to_dictionary()
	spy.serializations = 0
	for tick in 5: server._apply_skill_progression_event(event)
	_check(spy.serializations == 0 and mapper.calls == 0 and messages.is_empty(), "fractional progress has no whole-player/UI work")
	_check(spy.character_skills.driving.current_exp == 1 and is_equal_approx(spy.character_skills.driving.fractional_exp,0.5), "five times 0.1 * VIP2.5 * food1.2 accumulated exactly once")
	var after := spy.to_dictionary()
	after.erase("character_skills")
	before.erase("character_skills")
	_check(after == before, "equipment growth, inventory, warehouse, wallet, position, food and revisions preserved")
	_check(autosave.save_count == save_count+1, "ordinary fractions wait for the configured checkpoint")
	var persisted := server.player_state_repository.load_player(entity_id).value as PlayerStateRecord
	_check(persisted.character_skills.driving.current_exp == 0, "fractions not prematurely written")
	_check(autosave.advance(autosave.interval_seconds, _identity).is_ok, "scheduled whole-state persistence")
	_check((server.player_state_repository as FilePlayerStateRepository)._writer.flush().is_ok, "wait for queued checkpoint before reopening")
	var reopened := FilePlayerStateRepository.new(config.player_state_store_path)
	_check(reopened.initialize().is_ok, "reopen actual checkpoint file")
	persisted = reopened.load_player(entity_id).value
	_check(is_equal_approx(persisted.character_skills.driving.fractional_exp,0.5), "fractions survive reopening storage")
	state = autosave.state_for(entity_id)
	state.currency += 27
	state.food_status.active[0].expires_at = now-1
	_check(autosave.commit_player_state(entity_id,state).is_ok, "unrelated transaction and food expiry")
	var updated := autosave.apply_skill_progression(entity_id, service.grant_progression.bind(event))
	_check(updated.is_ok and is_equal_approx(updated.value.granted_experience,0.25), "expired food and forged event clock cannot add a multiplier")
	_check(autosave.state_for(entity_id).currency == state.currency, "fresh progression does not overwrite a concurrent equipment/economy transaction")
	var unknown := event.duplicate(true)
	unknown.source = "unknown"
	before = autosave.state_for(entity_id).to_dictionary()
	_check(not autosave.apply_skill_progression(entity_id, service.grant_progression.bind(unknown)).is_ok, "invalid source rejected")
	_check(autosave.state_for(entity_id).to_dictionary() == before, "invalid source does not mutate state")
	state = autosave.state_for(entity_id)
	state.character_skills.driving = {"level":10,"current_exp":0,"fractional_exp":0.0}
	_check(autosave.commit_player_state(entity_id,state).is_ok, "upgrade fixture")
	var upgrade := {"entity_id":entity_id,"source":"authoritative_action","skill_id":"driving","amount":1000000.0}
	before = autosave.state_for(entity_id).to_dictionary()
	var repository := autosave._repository
	autosave._repository = RejectingRepository.new()
	var denied := autosave.apply_skill_progression(entity_id, service.grant_progression.bind(upgrade))
	_check(not denied.is_ok and denied.error_code == &"test.disk_failure", "upgrade write failure propagated")
	_check(autosave.state_for(entity_id).to_dictionary() == before, "failed upgrade preserves skill and comprehensive level")
	autosave._repository = repository
	messages.clear()
	mapper.calls = 0
	server._apply_skill_progression_event(upgrade)
	state = autosave.state_for(entity_id)
	_check(state.character_skills.driving.level == 11 and state.character_skills.driving.current_exp == 0 and state.character_skills.driving.fractional_exp == 0.0, "one event grants only one level and discards excess")
	_check(state.character_level == SkillBook.new(state.character_skills).comprehensive_level(service._skill_progression_config), "comprehensive level stays consistent")
	_check(server.player_state_repository.load_player(entity_id).value.character_skills.driving.level == 11, "upgraded level is immediately committed in memory")
	_check(mapper.calls == 1 and messages.size() == 2 and messages[0].type == "skill_level_up" and messages[1].type == "player_panels", "upgrade publishes one rebuilt panel after memory commit")
	messages.clear()
	mapper.calls = 0
	server._apply_skill_progression_event({"entity_id":entity_id,"source":"effective_damage","skill_id":"energy_cannon","damage":7})
	_check(mapper.calls == 1 and messages.size() == 1 and messages[0].type == "player_panels", "visible percent still publishes current experience")
	var reentered := autosave.apply_skill_progression(entity_id, _reentrant.bind(event))
	_check(not reentered.is_ok and reentered.error_code == &"progression.stale", "nested settlement cannot overwrite inner progress")
	var leaked: PlayerSkillProgression
	var captured: Array[PlayerSkillProgression] = []
	updated = autosave.apply_skill_progression(entity_id, func(candidate: PlayerSkillProgression) -> DomainResult:
		captured.append(candidate)
		return service.grant_progression(candidate,event))
	_check(updated.is_ok, "captured isolated candidate")
	leaked = captured[0]
	before = autosave.state_for(entity_id).to_dictionary()
	leaked.skills.grant_experience("driving",123,service._skill_progression_config)
	leaked.level = 1
	leaked.food_status.physical = 1
	_check(autosave.state_for(entity_id).to_dictionary() == before, "retained candidate cannot mutate committed skill or food")
	server.free()
	print("SKILL_PROGRESSION_RUNTIME checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 把已登记的真实记录换成等价计数子类，保留全部字段及原始容器。
## 返回本测试拥有的记录观察器。
func _install_counting_record() -> CountingRecord:
	var source := server.autosave_service.state_for(entity_id)
	var spy := CountingRecord.new()
	for property: Dictionary in source.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			spy.set(property.name, source.get(property.name))
	server.autosave_service._states[entity_id] = spy
	return spy


## 以当前隔离快照执行正常自动存档，不推进地图或更改资源。
## [param state] 待持久化记录。
## 返回同一候选。
func _identity(state: PlayerStateRecord) -> DomainResult:
	return DomainResult.ok(state)


## 注入一次嵌套成长，验证外层候选不会覆盖内层已经提交的技能。
## [param candidate] 外层候选。[param event] 可信驾驶事件。
## 返回外层领域结算结果，最终提交应检测到旧快照。
func _reentrant(candidate: PlayerSkillProgression, event: Dictionary) -> DomainResult:
	server.autosave_service.apply_skill_progression(entity_id, server.player_panel_service.grant_progression.bind(event))
	return server.player_panel_service.grant_progression(candidate,event)


## 汇总状态及性能边界断言。
## [param condition] 条件。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
