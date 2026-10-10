class_name PlayerAchievements
extends RefCounted

var _catalog: AchievementCatalog
var _counters: Dictionary = {}
var _receipts: Dictionary = {}
var _points := 0


## 还原玩家成就账本；积分和最高称号由进度派生，绝不信任存档中的奖励字段。
## [param state] 经持久化边界校验的进度与已处理结算标识。
## [param catalog] 可注入测试规则；默认使用正式共享目录。
func _init(state: Dictionary = {}, catalog: AchievementCatalog = null) -> void:
	_catalog = catalog if catalog != null else AchievementCatalog.shared()
	_counters = (state.get("counters", {}) as Dictionary).duplicate(true)
	_receipts = (state.get("receipts", {}) as Dictionary).duplicate(true)
	for key: String in _counters:
		_counters[key] = int(_counters[key])
		_points += _catalog.points_for(key, _counters[key])


## 校验成就计数和幂等收据映射。
## [param state] 存档或网络状态。
## 返回是否为合法非负计数和幂等收据映射。
static func valid_state(state: Variant) -> bool:
	if not state is Dictionary or not state.get("counters", {}) is Dictionary \
		or not state.get("receipts", {}) is Dictionary:
		return false
	for key: Variant in state.get("counters", {}):
		var value: Variant = state["counters"][key]
		if not key is String or not (value is int or value is float) \
			or not is_finite(float(value)) or float(value) < 0 or float(value) > 1000000 \
			or float(value) != floorf(float(value)):
			return false
	for key: Variant in state.get("receipts", {}):
		if not key is String or state["receipts"][key] != true:
			return false
	return true


## 校验完整当前存档字段集。
## [param state] 玩家存档中的完整成就字段。
## 返回是否包含且仅包含计数与收据。
static func valid_persisted_state(state: Variant) -> bool:
	return state is Dictionary and state.size() == 2 and state.has("counters") \
		and state.has("receipts") and valid_state(state)


## 消费一次权威事实；按目标累计、跨阶一次结算，并永久拒绝重复收据。
## [param event] 击杀、矿物入包或任务成功交付事件。
## 返回是否改变了进度；未知目标、重复事件及已满进度均不写账本。
func record(event: AchievementEvent) -> bool:
	var change := prepare(event)
	commit(change)
	return not change.is_empty()


## 校验事实并准备本次计数与收据，不复制累计历史。
## [param event] 权威事实。
## 返回本次可提交的变更；重复或无效事实为空。
func prepare(event: AchievementEvent) -> Dictionary:
	if event == null or not event.is_valid(): return {}
	var key := event.counter_key()
	var receipt := "%s:%s" % [AchievementEvent.KIND_IDS[event.kind], event.event_id]
	var cap := int(_catalog.caps.get(key, 0))
	var previous := int(_counters.get(key, 0))
	if cap <= previous or _receipts.has(receipt): return {}
	return {"key": key, "count": mini(cap, previous + event.quantity), "receipt": receipt}


## 同步提交已准备的计数和收据；调用期间不发布信号。
## [param change] 紧邻提交前由本对象准备的变更。
func commit(change: Dictionary) -> void:
	if change.is_empty(): return
	_set_counter(change.key, change.count)
	_receipts[change.receipt] = true


## 客户端应用已经校验的最终计数，服务端收据不进入网络。
## [param counters] 仅包含发生变化的计数。
func apply_counters(counters: Dictionary) -> void:
	for key: String in counters: _set_counter(key, int(counters[key]))


## 提交目标计数时同步更新派生积分；服务端事实和客户端最终值共用规则。
## [param key] 目标身份。[param count] 已验证的最终计数。
func _set_counter(key: String, count: int) -> void:
	_points += _catalog.points_for(key, count) - _catalog.points_for(key, int(_counters.get(key, 0)))
	_counters[key] = count


## 读取由目标计数派生的积分；仅在载入时汇总，后续按变化目标更新。
## 返回总成就点。
func total_points() -> int:
	return _points


## 获取当前最高称号的独立增益对象。
## 返回唯一生效称号的增益；空目录为零增益。
func bonuses() -> AchievementBonuses:
	var rank := _catalog.title_for(total_points())
	return AchievementBonuses.new(rank.bonuses.to_dictionary()) if rank != null else AchievementBonuses.new()


## 序列化原始进度和去重收据，奖励由规则重新推导。
## 返回隔离的持久化字典。
func to_dictionary() -> Dictionary:
	return {"counters": _counters.duplicate(true), "receipts": _receipts.duplicate(true)}


## 生成紧凑的权威网络状态，不随每次结算重复传输静态成就目录和收据。
## 返回积分、称号、增益与目标计数。
func network_snapshot() -> Dictionary:
	var points := total_points()
	var current := _catalog.title_for(points)
	return {"points": points, "title_id": current.id if current != null else "",
		"title_name": current.display_name if current != null else "未获得称号",
		"bonuses": bonuses().to_dictionary(), "counters": _counters.duplicate(true)}


## 生成不泄露事件收据的成就与称号展示投影。
## 返回总积分、当前称号、称号阶梯及分类成就进度。
func snapshot() -> Dictionary:
	var points := total_points()
	var current := _catalog.title_for(points)
	var entries: Array[Dictionary] = []
	var ranks: Array[Dictionary] = []
	for row: AchievementCatalog.Definition in _catalog.definitions:
		var progress := mini(row.required, int(_counters.get("%s:%s" % [row.category, row.target_id], 0)))
		entries.append({"id": row.id, "category": row.category, "target_id": row.target_id,
			"target_name": row.target_name, "required": row.required, "progress": progress,
			"points": row.points, "completed": progress >= row.required})
	for rank: AchievementCatalog.Title in _catalog.titles:
		ranks.append({"id": rank.id, "name": rank.display_name, "required_points": rank.required_points,
			"unlocked": points >= rank.required_points, "active": rank == current,
			"bonuses": rank.bonuses.to_dictionary()})
	var result := network_snapshot()
	result["titles"] = ranks
	result["entries"] = entries
	return result
