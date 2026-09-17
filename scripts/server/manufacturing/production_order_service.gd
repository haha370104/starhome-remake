class_name ProductionOrderService
extends RefCounted

const COMMANDS := ["start_production", "pause_production", "resume_production", "cancel_production"]

var _catalog: ItemCatalog
var _book: ManufacturingRecipeBook
var _mapper: PlayerStateMapper
var _rules: ProductionRules
var _progression: Dictionary
var _random := RandomNumberGenerator.new()


## 复用制造服务已加载的目录与映射，仅编排订单事务和权威随机。
## [param catalog] 共享物品目录。
## [param book] 共享配方书。
## [param mapper] 同服务器奖励切面的玩家映射。
## [param rules] 服务器生产规则。
## [param progression] 原技能成长配置。
func _init(catalog: ItemCatalog, book: ManufacturingRecipeBook, mapper: PlayerStateMapper, rules: ProductionRules, progression: Dictionary) -> void:
	_catalog = catalog
	_book = book
	_mapper = mapper
	_rules = rules
	_progression = progression
	_random.randomize()


## 将网络意图转换为订单行为，费用、周期、身份、完成次数不接受客户端覆盖。
## [param state] 已绑定会话且捕获当前位置的存档副本。
## [param command] 原始订单命令；调用方先核验开始/继续地点有该设施。
## 返回仍需由调用方原子提交的候选和结果。
func execute(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	var kind: Variant = command.get("type")
	if kind not in COMMANDS or not ProductionQueue.valid_integer(command.get("production_revision"), 0, 9007199254740991):
		return DomainResult.failure(&"production.command", "生产命令缺少有效订单版本")
	var expected := int(command.production_revision)
	if kind == "start_production": return _start(state, command, expected)
	var candidate := state.duplicate_record()
	if kind == "cancel_production" and command.has("order_id"):
		return _cancel_named_order(candidate, command)
	var checked := candidate.production.require_revision(expected)
	if not checked.is_ok: return checked
	if candidate.production.order == null:
		return DomainResult.failure(&"production.no_order", "当前没有生产订单")
	var station := candidate.production.order.station_id
	var message := ""
	match kind:
		"pause_production":
			if not candidate.production.pause("已手动暂停"):
				return DomainResult.failure(&"production.not_running", "订单已经暂停")
			message = "已暂停生产，未完成轮次没有扣料"
		"resume_production":
			checked = candidate.production.resume(state.map_id, expected)
			if not checked.is_ok: return checked
			message = "已继续生产"
		"cancel_production":
			if not command.get("confirm_cancel") is bool or not command.confirm_cancel:
				return DomainResult.failure(&"production.confirm", "请确认取消尚未完成的生产轮次")
			checked = candidate.production.cancel(expected)
			if not checked.is_ok: return checked
			message = "已取消%d轮，保留已完成%d轮的成果" % [checked.value.canceled, checked.value.completed]
	return _result(candidate, station, String(kind), message)


## 取消明确的一份订单，完成次数变化不使确认失效，另一份订单绝不接受旧身份。
## [param candidate] 已隔离的角色副本。[param command] 含确认标志和原订单身份的意图。
## 返回实际取消轮次的候选；不信任客户端声称的剩余次数。
func _cancel_named_order(candidate: PlayerStateRecord, command: Dictionary) -> DomainResult:
	if not command.get("order_id") is String or not command.get("confirm_cancel") is bool or not command.confirm_cancel:
		return DomainResult.failure(&"production.confirm", "请确认取消指定生产订单的剩余轮次")
	var station := candidate.production.order.station_id if candidate.production.order != null else ""
	var canceled := candidate.production.cancel_order(command.order_id)
	if not canceled.is_ok: return canceled
	return _result(candidate, station, "cancel_production", "已取消%d轮，保留已完成%d轮的成果" % [canceled.value.canceled, canceled.value.completed])


## 核验开始意图的数量、库存版本和配方归属后创建订单，保持背包未扣料。
## [param state] 当前权威人物状态。
## [param command] 仅提取配方、次数与速度。
## [param expected] 已校验的订单版本。
## 返回新订单候选。
func _start(state: PlayerStateRecord, command: Dictionary, expected: int) -> DomainResult:
	if not ProductionQueue.valid_integer(command.get("inventory_revision"), 0, 9007199254740991) \
		or not ProductionQueue.valid_integer(command.get("cycles"), 1, _rules.maximum_cycles) \
		or not ProductionQueue.valid_integer(command.get("speed"), 1, _rules.maximum_speed) \
		or not command.get("recipe_id") is String or not command.get("station_id") is String:
		return DomainResult.failure(&"production.command", "请输入有效的生产次数和速度")
	var recipe: ManufacturingRecipe = _book.recipe(command.recipe_id)
	if recipe == null or not recipe.belongs_to_station(command.station_id):
		return DomainResult.failure(&"manufacturing.recipe_missing", "当前设施不能生产该配方")
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok: return mapped
	var player: Player = mapped.value
	var checked := player.inventory.require_revision(int(command.inventory_revision))
	if not checked.is_ok: return checked
	checked = player.production.start(recipe, player, int(command.cycles), int(command.speed),
		"production." + Crypto.new().generate_random_bytes(16).hex_encode(), _rules, expected)
	if not checked.is_ok: return checked
	var saved := _mapper.to_record(player)
	return _result(saved.value, recipe.station_id, "start_production", "已开始生产：%d轮，速度%d" % [int(command.cycles), int(command.speed)]) if saved.is_ok else saved


## 只供服务器时钟调用，结算一轮后更新库存、经验和进度；失败转为可继续的暂停订单。
## [param state] 已捕获到期时间及当前位置的权威副本。
## 返回同一提交中的完整候选，不能由客户端请求“完成”。
func complete(state: PlayerStateRecord) -> DomainResult:
	var mapped := _mapper.to_domain(state)
	if not mapped.is_ok: return mapped
	var player: Player = mapped.value
	var order := player.production.order
	if order == null or order.paused or order.remaining_milliseconds > 0:
		return DomainResult.failure(&"production.not_ready", "生产轮尚未到期")
	var recipe: ManufacturingRecipe = _book.recipe(order.recipe_id)
	var rolls: Array[float] = []
	for index in range(order.speed): rolls.append(_random.randf())
	var settled := player.production.complete_cycle(player, recipe, _catalog,
		"crafted." + Crypto.new().generate_random_bytes(16).hex_encode(), _random.randf(), _progression, rolls)
	var message := ""
	if not settled.is_ok:
		player.production.pause(settled.error_message)
		message = "生产已暂停：" + settled.error_message
	else:
		message = "已完成%d/%d轮：%s" % [int(settled.value.completed), int(settled.value.cycles),
			"生产成功" if settled.value.succeeded else "生产失败，本轮材料已消耗"]
	var saved := _mapper.to_record(player)
	if not saved.is_ok: return saved
	var result := _result(saved.value, order.station_id, "production_cycle", message)
	if settled.is_ok: result.value.operation.merge(settled.value, true)
	return result


## 构造同一权威提交接口使用的结果，不把未提交状态直接发布到客户端。
## [param state] 候选记录。
## [param station] 本次订单对应设施。
## [param action] 操作语义。
## [param message] 人类可读结果。
## 返回标准候选与操作摘要。
static func _result(state: PlayerStateRecord, station: String, action: String, message: String) -> DomainResult:
	return DomainResult.ok({"candidate": state, "changed": true,
		"operation": {"station_id": station, "action": action, "message": message}})
