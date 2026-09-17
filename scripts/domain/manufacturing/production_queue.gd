class_name ProductionQueue
extends RefCounted

class Order extends RefCounted:
	var id := ""
	var recipe_id := ""
	var station_id := ""
	var map_id := ""
	var cycles := 1
	var speed := 1
	var completed := 0
	var cycle_milliseconds := 2000
	var remaining_milliseconds := 2000
	var paused := false
	var pause_reason := ""

	## 保存订单原始事实，不保存产物或已经扣除的虚构材料。
	## 返回独立的持久化字段。
	func to_dictionary() -> Dictionary:
		return {"id": id, "recipe_id": recipe_id, "station_id": station_id, "map_id": map_id,
			"cycles": cycles, "speed": speed, "completed": completed, "cycle_milliseconds": cycle_milliseconds,
			"remaining_milliseconds": remaining_milliseconds, "paused": paused, "pause_reason": pause_reason}

var revision := 0
var order: Order = null


## 建立一份按轮次执行的订单，只检查本轮条件，不预扣整份订单材料。
## [param recipe] 权威配方书中的配方。
## [param player] 此队列所属玩家。
## [param cycles] 总轮数。
## [param speed] 每轮份数。
## [param identity] 服务端生成的订单身份。
## [param rules] 服务端周期与数量限制。
## [param expected_revision] 读取到的订单版本。
## 返回成功或拒绝原因；背包与经验均不改变。
func start(recipe: ManufacturingRecipe, player: Player, cycles: int, speed: int, identity: String, rules: ProductionRules, expected_revision: int) -> DomainResult:
	var checked := require_revision(expected_revision)
	if not checked.is_ok: return checked
	if order != null: return DomainResult.failure(&"production.busy", "已有生产订单，请先取消或完成")
	if recipe == null or rules == null or player == null or player.production != self or identity.is_empty() \
		or player.map_id.is_empty() or recipe.recipe_id.is_empty() or recipe.station_id.is_empty() \
		or cycles < 1 or cycles > rules.maximum_cycles or speed < 1 or speed > rules.maximum_speed:
		return DomainResult.failure(&"production.invalid_order", "生产次数、速度或配方无效")
	if recipe.success_probability(player.skills.effective_level(recipe.skill_id, player.character_equipment)) <= 0:
		return DomainResult.failure(&"manufacturing.skill_insufficient", "生产技能不足，当前成功率为零")
	checked = player.inventory._validate_requirements(ManufacturingBatch.requirements(recipe, speed))
	if not checked.is_ok: return checked
	order = Order.new()
	order.id = identity
	order.recipe_id = recipe.recipe_id
	order.station_id = recipe.station_id
	order.map_id = player.map_id
	order.cycles = cycles
	order.speed = speed
	order.cycle_milliseconds = rules.cycle_milliseconds
	order.remaining_milliseconds = rules.cycle_milliseconds
	revision += 1
	return DomainResult.ok(order)


## 暂停当前订单，已经暂停时不重复推进版本。
## [param reason] 显示给玩家的暂停原因。
## 返回是否由运行变为暂停。
func pause(reason: String) -> bool:
	if order == null or order.paused: return false
	order.paused = true
	order.pause_reason = reason
	revision += 1
	return true


## 在原设施地图恢复剩余轮次，不重置已经完成的次数。
## [param map_id] 权威当前位置。
## [param expected_revision] 当前订单版本。
## 返回恢复结果。
func resume(map_id: String, expected_revision: int) -> DomainResult:
	var checked := require_revision(expected_revision)
	if not checked.is_ok: return checked
	if order == null or not order.paused:
		return DomainResult.failure(&"production.not_paused", "没有可继续的暂停订单")
	if map_id != order.map_id:
		return DomainResult.failure(&"production.location", "请返回开始生产时的设施地图")
	order.paused = false
	order.pause_reason = ""
	revision += 1
	return DomainResult.ok(order)


## 取消尚未完成的轮次，未扣料的等待阶段没有返还交易。
## [param expected_revision] 当前订单版本。
## 返回已完成与取消的轮数；旧意图不能取消下一份订单。
func cancel(expected_revision: int) -> DomainResult:
	var checked := require_revision(expected_revision)
	if not checked.is_ok: return checked
	if order == null: return DomainResult.failure(&"production.no_order", "当前没有生产订单")
	var result := {"completed": order.completed, "canceled": order.cycles - order.completed}
	order = null
	revision += 1
	return DomainResult.ok(result)


## 将权威时钟的剩余等待写入同订单快照，不因计时改变操作版本。
## [param id] 时钟所属的订单。
## [param expected_revision] 时钟建立时的订单版本。
## [param remaining] 时钟计算的剩余毫秒。
## 返回是否仍匹配当前运行订单。
func capture_remaining(id: String, expected_revision: int, remaining: int) -> bool:
	if order == null or order.id != id or revision != expected_revision or order.paused \
		or remaining < 0 or remaining > order.cycle_milliseconds:
		return false
	order.remaining_milliseconds = remaining
	return true


## 完成到期的一轮并把批量结算与订单进度同时提交到所属聚合。
## [param player] 当前隔离玩家聚合。
## [param recipe] 订单绑定的权威配方。
## [param catalog] 具体物品工厂。
## [param identity] 本轮产物的服务端唯一前缀。
## [param random_roll] 一轮成功率随机值。
## [param progression_config] 原技能成长规则。
## [param quality_rolls] 与订单速度一致的每份品质随机数。
## 返回本轮结果；任何失败均不推进已完成次数。
func complete_cycle(player: Player, recipe: ManufacturingRecipe, catalog: ItemCatalog, identity: String,
		random_roll: float, progression_config: Dictionary, quality_rolls: Array[float]) -> DomainResult:
	if order == null or order.paused or order.remaining_milliseconds > 0 or player == null or player.production != self:
		return DomainResult.failure(&"production.not_ready", "当前生产轮尚未就绪")
	if player.map_id != order.map_id or recipe == null or recipe.recipe_id != order.recipe_id \
		or recipe.station_id != order.station_id or quality_rolls.size() != order.speed:
		return DomainResult.failure(&"production.order_mismatch", "生产地点、配方或速度与订单不符")
	var settled := ManufacturingBatch.execute(recipe, player, catalog, identity, random_roll, progression_config, quality_rolls)
	if not settled.is_ok: return settled
	order.completed += 1
	revision += 1
	settled.value["completed"] = order.completed
	settled.value["cycles"] = order.cycles
	settled.value["order_done"] = order.completed == order.cycles
	if order.completed == order.cycles: order = null
	else: order.remaining_milliseconds = order.cycle_milliseconds
	return settled


## 校验订单意图的独立版本，普通背包整理和自动存档不影响此版本。
## [param expected_revision] 客户端看到的订单版本。
## 返回是否允许操作。
func require_revision(expected_revision: int) -> DomainResult:
	return DomainResult.ok() if expected_revision == revision else DomainResult.failure(&"production.revision", "生产订单已经变化，请刷新后重试")


## 保存单份订单及独立版本，空订单仍保留版本以拒绝历史取消命令。
## 返回JSON安全字段。
func to_dictionary() -> Dictionary:
	var state: Variant = null
	if order != null: state = order.to_dictionary()
	return {"version": 1, "revision": revision, "order": state}


## 为映射与候选事务复制订单，避免不同人物快照共享可写状态。
## 返回独立的领域队列。
func duplicate_queue() -> ProductionQueue:
	return restore(to_dictionary()).value


## 校验可选的新存档字段；旧档缺失时得到空订单，非法订单整体拒绝。
## [param raw] 读盘的订单状态。
## 返回合法领域队列或字段错误。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary: return DomainResult.failure(&"production.state", "生产订单存档不是对象")
	var queue := ProductionQueue.new()
	if raw.is_empty(): return DomainResult.ok(queue)
	if not valid_integer(raw.get("version"), 1, 1) or not valid_integer(raw.get("revision"), 0, 9007199254740991):
		return DomainResult.failure(&"production.state", "生产订单版本无效")
	queue.revision = int(raw.revision)
	var value: Variant = raw.get("order")
	if value == null: return DomainResult.ok(queue)
	if not value is Dictionary: return DomainResult.failure(&"production.state", "生产订单内容无效")
	for key: String in ["id", "recipe_id", "station_id", "map_id"]:
		if not value.get(key) is String or value[key].is_empty():
			return DomainResult.failure(&"production.state", "生产订单缺少身份或地点")
	if not valid_integer(value.get("cycles"), 1, 10000) or not valid_integer(value.get("speed"), 1, 10) \
		or not valid_integer(value.get("completed"), 0, int(value.get("cycles", 0)) - 1) \
		or not valid_integer(value.get("cycle_milliseconds"), 100, 60000) \
		or not valid_integer(value.get("remaining_milliseconds"), 0, int(value.get("cycle_milliseconds", 0))) \
		or not value.get("paused") is bool or not value.get("pause_reason") is String:
		return DomainResult.failure(&"production.state", "生产订单计数或等待状态无效")
	queue.order = Order.new()
	for key: String in ["id", "recipe_id", "station_id", "map_id", "pause_reason", "paused"]: queue.order.set(key, value[key])
	for key: String in ["cycles", "speed", "completed", "cycle_milliseconds", "remaining_milliseconds"]: queue.order.set(key, int(value[key]))
	return DomainResult.ok(queue)


## 验证网络或存档整数，拒绝布尔、小数、无穷和越界值。
## [param value] 待检查数值。
## [param minimum] 包含的下限。
## [param maximum] 包含的上限。
## 返回是否符合整数范围。
static func valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum
