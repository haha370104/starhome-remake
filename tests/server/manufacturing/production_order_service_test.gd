extends SceneTree

var checks := 0
var failures: Array[String] = []
var service := AuthoritativeManufacturingService.new()
var recipe: ManufacturingRecipe


## 验证订单RPC边界与定时结算入口的分离，不把客户端等待当成生产完成。
func _initialize() -> void:
	_check(service.initialize().is_ok, "制造服务")
	for candidate: ManufacturingRecipe in service._recipe_book.recipes_for_station("refining"):
		if service._item_catalog.display_name(candidate.product_definition_id) == "铁": recipe = candidate
	_check(recipe != null, "真实铁矿提炼配方")
	var state := _state()
	var command := _start(state)
	var original := state.to_dictionary()
	for key: String in ["cycles", "speed", "inventory_revision", "production_revision"]:
		for value: Variant in [true, "1", 1.5, INF, -1]:
			var invalid := command.duplicate(true)
			invalid[key] = value
			_check(not service.execute(state, invalid).is_ok, "严格数量/版本：" + key)
	var outside := state.duplicate_record()
	outside.map_id = "outside"
	command.map_id = state.map_id
	_check(not service.execute(outside, command).is_ok, "不能伪造所在地")
	command["cycle_milliseconds"] = 0
	command["id"] = "client.chosen"
	command["completed"] = 9999
	command["remaining_milliseconds"] = 0
	var started := service.execute(state, command)
	_check(started.is_ok and state.to_dictionary() == original, "开始只构造隔离候选")
	state = started.value.candidate
	_check(state.production.order.id != "client.chosen" and state.production.order.cycle_milliseconds == 2000 and state.production.order.completed == 0, "身份周期和完成次数服务端决定")
	_check(_count(state, recipe.materials[0].definition_id) == 50, "等待不扣料")
	_check(not service.execute(state, command).is_ok, "重放开始拒绝")
	_check(not service.execute(state, {"type": "complete_production_cycle", "station_id": "refining"}).is_ok, "没有客户端完成命令")
	_check(not service.complete_production_cycle(state).is_ok, "时钟未到拒绝")
	_check(not service.execute(state, {"type": "craft_recipe", "station_id": "refining", "recipe_id": recipe.recipe_id, "inventory_revision": state.inventory_revision}).is_ok, "订单运行期间旧单次入口不能并行结算")
	var query := service.execute(state, {"type": "query_production"})
	_check(query.is_ok and not query.value.changed and query.value.panel_bundle.manufacturing.production.order.speed == 2, "查询只读订单和规则")
	for completed in range(1, 3):
		state.production.capture_remaining(state.production.order.id, state.production.revision, 0)
		var cycle := service.complete_production_cycle(state)
		_check(cycle.is_ok and cycle.value.operation.completed == completed, "实际完成轮次%d" % completed)
		state = cycle.value.candidate
		_check(_count(state, recipe.product_definition_id) == completed * 2, "按速度真实产物")
		_check(_count(state, recipe.materials[0].definition_id) == 50 - completed * 20, "按速度真实耗材")
	var before := state.to_dictionary()
	state.production.capture_remaining(state.production.order.id, state.production.revision, 0)
	var stopped := service.complete_production_cycle(state)
	_check(stopped.is_ok and stopped.value.candidate.production.order.paused and stopped.value.candidate.production.order.completed == 2, "材料不足暂停保留剩余轮次")
	state = stopped.value.candidate
	_check(_count(state, recipe.materials[0].definition_id) == 10 and state.inventory_revision == before.inventory_revision, "材料不足不扣半轮")
	_check(not service.complete_production_cycle(state).is_ok, "暂停订单不能再次完成")
	var saved: PlayerStateRecord = PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(state.to_dictionary()))).value
	_check(saved.production.order.completed == 2 and saved.production.order.paused, "真实JSON重读")
	var resume := {"type": "resume_production", "production_revision": state.production.revision}
	outside = state.duplicate_record()
	outside.map_id = "dragon_city_refinery_floor_2"
	_check(not service.execute(outside, resume).is_ok, "有相同设施也不能异图继续旧订单")
	var canceled := {"type": "cancel_production", "production_revision": state.production.revision}
	_check(not service.execute(state, canceled).is_ok, "取消需要明确确认")
	canceled.confirm_cancel = true
	outside.map_id = "outside"
	var canceled_result := service.execute(outside, canceled)
	_check(canceled_result.is_ok and canceled_result.value.candidate.production.order == null, "可在野外取消剩余轮次")
	_check(_count(canceled_result.value.candidate, recipe.materials[0].definition_id) == 10, "取消不虚构材料返还")
	_check(not service.execute(canceled_result.value.candidate, canceled).is_ok, "重复取消拒绝")
	var active := _state()
	active = service.execute(active, _start(active)).value.candidate
	active.map_id = "outside"
	var paused := service.complete_production_cycle(active)
	_check(paused.is_ok and paused.value.candidate.production.order.paused and _count(paused.value.candidate, recipe.materials[0].definition_id) == 50, "换图只暂停没有产物或扣料")
	for failure in failures: push_error(failure)
	print("Production order service: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)


## 创建真实提炼厂的隔离存档，准备50个原配方矿石。
## 返回可以建立两档订单的记录。
func _state() -> PlayerStateRecord:
	var fixture := PlayerPanelServiceFixture.new()
	fixture.initialize()
	var player: Player = service._mapper.to_domain(fixture._state).value
	player.map_id = "glory_nft_bl_factory1"
	player.skills = SkillBook.new({"refining": 100})
	player.inventory = Inventory.new()
	player.inventory.add_reward(service._item_catalog.create(recipe.materials[0].definition_id, {"instance_id": "ore", "quantity": 50}).value)
	return service._mapper.to_record(player).value


## 构造带双版本的三轮二档订单。
## [param state] 当前记录。
## 返回纯客户端意图。
func _start(state: PlayerStateRecord) -> Dictionary:
	return {"type": "start_production", "station_id": "refining", "recipe_id": recipe.recipe_id,
		"cycles": 3, "speed": 2, "inventory_revision": state.inventory_revision, "production_revision": state.production.revision}


## 读取实际存档中的数量，不使用UI预测值。
## [param state] 当前存档。
## [param id] 物品定义。
## 返回所有堆叠总数量。
func _count(state: PlayerStateRecord, id: String) -> int:
	var count := 0
	for item: InventoryStackRecord in state.inventory_stacks:
		if item.item_definition_id == id: count += item.quantity
	return count


## 累计RPC边界及候选一致性断言。
## [param condition] 预期条件。
## [param label] 故障定位。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
