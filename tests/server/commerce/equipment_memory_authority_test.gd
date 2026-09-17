extends SceneTree

var checks := 0
var failures := 0


## 通过正式服务验证载荷不能伪造、确认不能绕过及保存后的真实转移。
func _initialize() -> void:
	var items := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	var service := AuthoritativeCommerceService.new()
	_check(items.initialize().is_ok and fixture.initialize().is_ok and service.initialize().is_ok, "初始化")
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory.currency = 100000
	player.inventory.add_reward(items.create("beginner_engine", {"instance_id": "source", "strengthening": {"level": 3}}).value)
	player.inventory.add_reward(items.create("equipment_memory_strengthening", {"instance_id": "module"}).value)
	player.inventory.add_reward(items.create("equipment_memory_stabilizer", {"instance_id": "stabilizer", "quantity": 2}).value)
	var state: PlayerStateRecord = mapper.to_record(player).value
	var command := {"type": "process_equipment_memory", "instance_id": "source", "material_id": "module", "mode": "extract", "use_stabilizer": true, "inventory_revision": state.inventory_revision,
		"confirm_transfer": true, "payload": {"level": 10}}
	var before := state.to_dictionary()
	var result := service.execute(state, command)
	_check(result.is_ok and state.to_dictionary() == before, "隔离事务")
	if not result.is_ok: push_error(result.error_message); quit(1); return
	player = mapper.to_domain(result.value.candidate).value
	_check(player.inventory.find("source").strengthening.level == 0 and player.inventory.find("module").memory.strengthening.level == 3, "真实载荷而非客户端伪造")
	_check(player.inventory.find("stabilizer").quantity == 1, "只消耗一个稳压剂")
	_check(not result.value.panel_bundle.equipment_memory.preview.has("candidate"), "不传输领域候选")
	_check(not service.execute(result.value.candidate, command).is_ok, "重复请求拒绝")
	command.mode = "transfer"
	command.instance_id = "inventory.spare_engine"
	command.inventory_revision = player.inventory.revision
	command.confirm_transfer = false
	_check(not service.execute(result.value.candidate, command).is_ok, "要求后果确认")
	command.confirm_transfer = true
	var query := command.duplicate(true)
	query.type = "query_equipment_memory"
	var preview := service.execute(result.value.candidate, query)
	_check(preview.is_ok and not preview.value.changed, "查询无副作用")
	_check(preview.value.panel_bundle.equipment_memory.preview.text.contains("3星") and preview.value.panel_bundle.equipment_memory.preview.text.contains("100%"), "可读成长与概率")
	_check(preview.value.panel_bundle.equipment_memory.offers.size() == 7, "完整供给")
	var transferred := service.execute(result.value.candidate, command)
	_check(transferred.is_ok, "权威转移")
	player = mapper.to_domain(transferred.value.candidate).value
	_check(player.inventory.find("module") == null and player.inventory.find("inventory.spare_engine").strengthening.level == 3 and player.inventory.find("inventory.spare_engine").drive == 26, "实际属性恢复")
	var bought := service.execute(transferred.value.candidate, {"type": "buy_equipment_memory_item", "definition_id": "equipment_memory_strengthening", "quantity": 1, "inventory_revision": player.inventory.revision, "price": 0})
	_check(bought.is_ok and bought.value.candidate.currency == 99980, "原价购买")
	var rejected := service.execute(transferred.value.candidate, {"type": "buy_equipment_memory_item", "definition_id": "equipment_memory_strengthening", "quantity": 2, "inventory_revision": player.inventory.revision})
	_check(not rejected.is_ok, "模块不可堆叠")
	print("Equipment memory authority: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## 记录服务事务断言。
## [param condition] 当前结果。
## [param label] 诊断说明。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
