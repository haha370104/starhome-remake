class_name DailyActivityJournal
extends RefCounted

var _state: Dictionary


## 恢复玩家每日活动账本；旧存档使用空账本，不发放奖励。
## [param saved] 已通过持久化边界校验的纯状态。
func _init(saved: Dictionary = {}) -> void:
	_state = saved.duplicate(true)
	for key: String in ["active", "experience_counts", "experience_claims", "receipts"]:
		if not _state.has(key):
			_state[key] = {}
	for key: String in ["revision", "serial", "accepted_today", "completed_today", "points"]:
		_state[key] = int(_state.get(key, 0))
	for row: Dictionary in _state.active.values():
		row.progress = int(row.progress)
	for key: String in ["experience_counts", "experience_claims"]:
		for id: String in _state[key]:
			_state[key][id] = int(_state[key][id])
	if not _state.has("offers"):
		_state.offers = []
	if not _state.has("day"):
		_state.day = ""


## 校验存档容器及不可为负的计数，防止坏存档进入领域。
## [param raw] 持久化边界收到的可选活动字段。
## 返回字段是否可安全还原。
static func valid_state(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
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
	if String(_state.day) != day:
		_state.day = day
		_state.accepted_today = 0
		_state.completed_today = 0
		_state.experience_counts = {}
		_state.experience_claims = {}
		_state.offers = []
		_state.revision += 1
	if _state.offers.is_empty():
		_refresh(catalog, level)


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
	if death_id.is_empty() or _state.receipts.has(death_id):
		return false
	var changed := false
	for row: Dictionary in _state.active.values():
		var task: MercenaryDefinition = catalog.tasks.get(String(row.id))
		if task != null and task.kind == 1 and task.target_id == species_id and int(row.progress) < task.quantity:
			row.progress += 1
			changed = true
	for activity: Dictionary in catalog.experience:
		var id := String(activity.id)
		if bool(activity.enabled) and not String(activity.target_id).is_empty() and activity.target_id == species_id:
			var count := int(_state.experience_counts.get(id, 0))
			if count < int(activity.limit):
				_state.experience_counts[id] = count + 1
				changed = true
	if changed:
		_state.receipts[death_id] = true
		_state.revision += 1
	return changed


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
