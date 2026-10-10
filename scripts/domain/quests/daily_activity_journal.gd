class_name DailyActivityJournal
extends RefCounted

var _state: Dictionary


class Change extends RefCounted:
	var reset: Dictionary = {}
	var active: Dictionary = {}
	var experience: Dictionary = {}
	var receipt := ""
	var revision_steps := 0

	## 判断本计划是否包含可提交变化。
	## 返回是否需要推进日常账本版本。
	func changed() -> bool:
		return revision_steps > 0


## 恢复玩家每日活动账本。
## [param saved] 已通过持久化边界校验的纯状态。
func _init(saved: Dictionary = {}) -> void:
	_state = {
		"active": {}, "experience_counts": {}, "experience_claims": {}, "receipts": {},
		"revision": 0, "serial": 0, "accepted_today": 0, "completed_today": 0,
		"points": 0, "offers": [], "day": "",
	} if saved.is_empty() else saved.duplicate(true)
	for row: Dictionary in _state.active.values():
		row.progress = int(row.progress)
	for key: String in ["experience_counts", "experience_claims"]:
		for id: String in _state[key]:
			_state[key][id] = int(_state[key][id])


## 校验存档容器及不可为负的计数，防止坏存档进入领域。
## [param raw] 持久化边界收到的可选活动字段。
## 返回字段是否可安全还原。
static func valid_state(raw: Variant) -> bool:
	if not raw is Dictionary or raw.size() != 11:
		return false
	for key: String in ["active", "experience_counts", "experience_claims", "receipts", "revision",
		"serial", "accepted_today", "completed_today", "points", "offers", "day"]:
		if not raw.has(key): return false
	for key: String in ["active", "experience_counts", "experience_claims", "receipts"]:
		if not raw.get(key, {}) is Dictionary:
			return false
		for id: Variant in raw.get(key, {}):
			if not id is String or String(id).is_empty():
				return false
	for key: String in ["revision", "serial", "accepted_today", "completed_today", "points"]:
		if not _valid_count(raw.get(key, 0)):
			return false
	if not raw.get("offers", []) is Array or not raw.get("day", "") is String:
		return false
	for id: Variant in raw.get("offers", []):
		if not id is String or String(id).is_empty():
			return false
	for row: Variant in raw.get("active", {}).values():
		if not row is Dictionary or not row.get("id", "") is String or String(row.get("id", "")).is_empty() \
			or not _valid_count(row.get("progress", -1)):
			return false
	for key: String in ["experience_counts", "experience_claims"]:
		for count: Variant in raw.get(key, {}).values():
			if not _valid_count(count):
				return false
	for receipt: Variant in raw.get("receipts", {}).values():
		if not receipt is bool or not receipt:
			return false
	return true


## 接受 JSON 解码后的整数浮点表示，同时拒绝小数、字符串和溢出值。
## [param value] 存档边界收到的计数。
## 返回是否为可安全转换的非负整数。
static func _valid_count(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 \
		and float(value) <= 1000000000000 and float(value) == floorf(float(value))


## 使用服务器日期换日；已接佣兵及击杀收据跨日保留，历练未领奖进度当日有效。
## [param day] 服务器按北京时间计算的业务日期。
## [param catalog] 权威任务规则。
## [param level] 玩家综合等级。
func prepare(day: String, catalog: DailyActivityCatalog, level: int) -> void:
	commit(prepare_day(day, catalog, level))


## 准备换日和可接任务，不复制跨日保留的死亡收据。
## [param day] 权威日期。[param catalog] 日常规则。[param level] 综合等级。
## 返回尚未写入账本的计划。
func prepare_day(day: String, catalog: DailyActivityCatalog, level: int) -> Change:
	var change := Change.new()
	var new_day := String(_state.day) != day
	if new_day:
		change.reset = {"day": day, "accepted_today": 0, "completed_today": 0,
			"experience_counts": {}, "experience_claims": {}}
		change.revision_steps += 1
	if new_day or _state.offers.is_empty():
		var candidates := catalog.eligible(level)
		for row: Dictionary in _state.active.values(): candidates.erase(String(row.id))
		candidates.shuffle()
		change.reset["offers"] = candidates.slice(0, mini(int(catalog.policy.board_size), candidates.size()))
		change.revision_steps += 1
	return change


## 抽取互不重复的可接任务；只由服务器调用，不接收客户端随机种子。
## [param catalog] 可完成目标目录。
## [param level] 当前综合等级。
func _refresh(catalog: DailyActivityCatalog, level: int) -> void:
	var candidates := catalog.eligible(level)
	for row: Dictionary in _state.active.values():
		candidates.erase(String(row.id))
	candidates.shuffle()
	_state.offers = candidates.slice(0, mini(int(catalog.policy.board_size), candidates.size()))
	_state.revision += 1


## 在领取次数、同时持有上限和版本一致时接取当前任务栏中的任务。
## [param id] 客户端选择的定义 ID。
## [param revision] 客户端看到的账本版本。
## [param catalog] 权威目录及每日限制。
## [param level] 当前综合等级。
## 返回接取结果或拒绝原因。
func accept(id: String, revision: int, catalog: DailyActivityCatalog, level: int) -> DomainResult:
	if revision != int(_state.revision):
		return _stale()
	if int(_state.accepted_today) >= int(catalog.policy.daily_limit) or _state.active.size() >= int(catalog.policy.active_limit):
		return DomainResult.failure(&"daily.limit", "今日领取次数或同时持有任务数已达上限")
	if id not in _state.offers or not catalog.eligible(level).has(id):
		return DomainResult.failure(&"daily.unavailable", "该任务不在当前可接列表中")
	_state.serial += 1
	var ticket := "%s:%d" % [_state.day, _state.serial]
	_state.active[ticket] = {"id": id, "progress": 0}
	_state.accepted_today += 1
	_refresh(catalog, level)
	return DomainResult.ok({"action": "mercenary_accept", "ticket": ticket})


## 放弃只删除该次任务，不退还每日领取次数。
## [param ticket] 本次接取的唯一实例 ID。
## [param revision] 客户端所见账本版本。
## 返回放弃结果。
func abandon(ticket: String, revision: int) -> DomainResult:
	if revision != int(_state.revision):
		return _stale()
	if not _state.active.erase(ticket):
		return DomainResult.failure(&"daily.not_active", "任务已不存在")
	_state.revision += 1
	return DomainResult.ok({"action": "mercenary_abandon"})


## 先检查每日完成上限，再验证进度和消费材料，关闭实例后返回唯一奖励凭据。
## [param ticket] 本次接取的唯一实例 ID。
## [param revision] 客户端账本版本。
## [param catalog] 服务端定义目录。
## [param inventory] 玩家聚合内部的权威背包。
## 返回应由玩家钱包入账的紫晶数。
func complete(ticket: String, revision: int, catalog: DailyActivityCatalog, inventory: Inventory) -> DomainResult:
	if revision != int(_state.revision):
		return _stale()
	if int(_state.completed_today) >= int(catalog.policy.completion_limit):
		return DomainResult.failure(&"daily.completion_limit", "今日已完成%d次佣兵任务，请明天再交付" % int(catalog.policy.completion_limit))
	var row: Dictionary = _state.active.get(ticket, {})
	var task: MercenaryDefinition = catalog.tasks.get(String(row.get("id", "")))
	if task == null:
		return DomainResult.failure(&"daily.not_active", "任务已不存在或目标尚未开放")
	if task.kind == 2:
		var consumed := task.consume_delivery(inventory)
		if not consumed.is_ok:
			return consumed
	elif int(row.progress) < task.quantity:
		return DomainResult.failure(&"daily.incomplete", "尚未完成任务目标")
	_state.active.erase(ticket)
	_state.completed_today += 1
	_state.points = mini(250000, int(_state.points) + task.points)
	for activity: Dictionary in catalog.experience:
		if String(activity.id) in ["8", "10"] and int(_state.completed_today) >= int(activity.condition[1]):
			_state.experience_counts[String(activity.id)] = 1
	_state.revision += 1
	return DomainResult.ok({"action": "mercenary_complete", "reward": task.reward, "ticket": ticket})


## 处理内部击杀事实，按死亡实例去重，客户端没有此操作入口。
## [param species_id] 服务端确认的怪物定义 ID。
## [param death_id] 服务端每次死亡的唯一 ID。
## [param catalog] 可完成目标目录。
## 返回是否改变进度。
func record_kill(species_id: String, death_id: String, catalog: DailyActivityCatalog) -> bool:
	var change := prepare_kill(species_id, death_id, catalog)
	commit(change)
	return change.changed()


## 准备一笔击杀涉及的任务计数；可与同事务换日计划合并。
## [param species_id] 物种。[param death_id] 死亡身份。[param catalog] 规则。[param change] 可选换日计划。
## 返回仅含本次最终计数及新增收据的计划。
func prepare_kill(species_id: String, death_id: String, catalog: DailyActivityCatalog, change: Change = null) -> Change:
	if change == null: change = Change.new()
	if death_id.is_empty() or _state.receipts.has(death_id): return change
	for ticket: String in _state.active:
		var row: Dictionary = _state.active[ticket]
		var task: MercenaryDefinition = catalog.tasks.get(String(row.id))
		if task != null and task.kind == 1 and task.target_id == species_id and int(row.progress) < task.quantity:
			change.active[ticket] = int(row.progress) + 1
	for activity: Dictionary in catalog.experience:
		var id := String(activity.id)
		if bool(activity.enabled) and not String(activity.target_id).is_empty() and activity.target_id == species_id:
			var count := 0 if change.reset.has("day") else int(_state.experience_counts.get(id, 0))
			if count < int(activity.limit): change.experience[id] = count + 1
	if not change.active.is_empty() or not change.experience.is_empty():
		change.receipt = death_id
		change.revision_steps += 1
	return change


## 无回调提交准备好的日常变更，不替换其他任务或历史收据。
## [param change] 本对象在同一同步事务中准备的计划。
func commit(change: Change) -> void:
	_state.merge(change.reset, true)
	for ticket: String in change.active: _state.active[ticket].progress = change.active[ticket]
	_state.experience_counts.merge(change.experience, true)
	if not change.receipt.is_empty(): _state.receipts[change.receipt] = true
	_state.revision += change.revision_steps


## 领取当日已达成且未入账的历练次数，不接受客户端奖励数值。
## [param id] 历练定义 ID。
## [param revision] 客户端看到的账本版本。
## [param catalog] 固定历练目录。
## 返回本次应入账的紫晶数。
func claim_experience(id: String, revision: int, catalog: DailyActivityCatalog) -> DomainResult:
	if revision != int(_state.revision):
		return _stale()
	for activity: Dictionary in catalog.experience:
		if String(activity.id) != id or not bool(activity.enabled):
			continue
		var count := int(_state.experience_counts.get(id, 0))
		var unpaid := count - int(_state.experience_claims.get(id, 0))
		if unpaid <= 0:
			break
		_state.experience_claims[id] = count
		_state.revision += 1
		return DomainResult.ok({"action": "experience_claim", "reward": unpaid * int(activity.reward)})
	return DomainResult.failure(&"daily.nothing_to_claim", "没有可领取的历练奖励")


## 序列化包含收据和跨日任务实例的完整账本。
## 返回可独立保存的状态副本。
func to_dictionary() -> Dictionary:
	return _state.duplicate(true)


## 构建统一版本的佣兵和历练投影，不改变进度或钱包。
## [param catalog] 权威目录。
## [param inventory] 用于投影实时收集材料数量的背包。
## 返回不包含死亡收据的窗口状态。
func snapshot(catalog: DailyActivityCatalog, inventory: Inventory) -> Dictionary:
	var result := {"revision": _state.revision, "day": _state.day, "accepted_today": _state.accepted_today,
		"completed_today": _state.completed_today, "points": _state.points, "offers": [], "active": [], "experience": []}
	for id: String in _state.offers:
		if catalog.tasks.has(id):
			result.offers.append(catalog.tasks[id].snapshot())
	for ticket: String in _state.active:
		var saved: Dictionary = _state.active[ticket]
		var task: MercenaryDefinition = catalog.tasks.get(String(saved.id))
		if task == null:
			continue
		var row := task.snapshot()
		row["ticket"] = ticket
		row["progress"] = task.delivery_progress(inventory) if task.kind == 2 else int(saved.progress)
		row["ready"] = int(row.progress) >= task.quantity
		result.active.append(row)
	for activity: Dictionary in catalog.experience:
		var row := activity.duplicate(true)
		row["progress"] = int(_state.experience_counts.get(String(row.id), 0))
		row["claimed"] = int(_state.experience_claims.get(String(row.id), 0))
		result.experience.append(row)
	return result


## 统一拒绝重复或过期窗口操作。
## 返回要求刷新任务面板的领域错误。
func _stale() -> DomainResult:
	return DomainResult.failure(&"daily.stale", "任务状态已变化，请刷新后重试")
