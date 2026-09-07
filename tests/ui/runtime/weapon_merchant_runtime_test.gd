extends SceneTree

const ManagerScript := preload("res://scripts/client/ui/windows/game_window_manager.gd")
const CommerceServiceScript := preload(
	"res://scripts/server/commerce/authoritative_commerce_service.gd"
)
const PanelFixtureScript := preload("res://tests/fixtures/player_panel_service_fixture.gd")

var failures: PackedStringArray = []
var assertions := 0
var _state: PlayerStateRecord
var _service


## 延迟启动商店窗口运行时测试，等待场景树可安全挂载控件。
func _initialize() -> void:
	call_deferred("_run")


## 用真实权威服务驱动商店窗口，覆盖查询、购买、出售和任务领取。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var fixture = PanelFixtureScript.new()
	var fixture_loaded: DomainResult = fixture.initialize()
	_service = CommerceServiceScript.new()
	var service_loaded: DomainResult = _service.initialize()
	_expect(fixture_loaded.is_ok and service_loaded.is_ok, "商店运行时依赖应初始化")
	if not fixture_loaded.is_ok or not service_loaded.is_ok:
		_finish(null)
		return
	_state = fixture._state
	_state.currency = 100000
	_test_equipment_purchase_scope()
	var manager = ManagerScript.new()
	root.add_child(manager)
	manager.configure(Callable(self, "_dispatch").bind(manager))
	manager.open_weapon_merchant("buy")
	await process_frame
	await process_frame
	var window: WeaponMerchantWindow = manager.weapon_merchant_window
	_expect(window.visible and window.current_mode() == "buy", "买东西应打开武器商人买入窗")
	_expect(window.size == Vector2(530, 450), "买卖窗应复现原版 530×450 尺寸")
	var offers: Array = window._commerce.get("offers", [])
	_expect(not offers.is_empty(), "武器商人应返回 270 级及以下装备")
	_expect(window._list.get_child_count() == offers.size(), "每项商品应对应一条 22 像素购买行")
	var currency_before := _state.currency
	window._request_trade(offers[0])
	await process_frame
	_expect(_state.currency < currency_before, "购买应由权威服务扣除金币")

	manager.open_weapon_merchant("sell")
	await process_frame
	await process_frame
	var sell_items: Array = window._commerce.get("sell_items", [])
	_expect(window.current_mode() == "sell" and not sell_items.is_empty(), "卖东西应列出背包全部物品")
	var sell_currency_before := _state.currency
	window._request_trade(sell_items[0])
	await process_frame
	_expect(_state.currency > sell_currency_before, "出售应由权威服务增加金币")

	manager.open_weapon_merchant("task")
	await process_frame
	_expect(window._task_root.visible and not window._list_scroll.get_parent().visible,
		"中级任务应显示消息窗而不是商品列表")
	_expect("低级类胶" in window._task_message.text, "任务消息应采用原版武器商人文案")
	window._request_task_action()
	await process_frame
	_expect(bool(_state.quest_states.arms_npc_supply.accepted), "接受任务应写入权威任务状态")
	_expect(window._task_primary_button.disabled, "材料不足时完成任务按钮应禁用")
	_finish(manager)


## 通过真实权威服务校验高档价格、地面维修臂购买和太空工程臂禁售。
## 设计：使用独立内存存档副本；客户端伪造低价不能改变结算，拒绝交易不得写入原状态。
func _test_equipment_purchase_scope() -> void:
	var state := _state.duplicate_record()
	var command := {
		"type": "buy_from_weapon_merchant",
		"definition_id": "glory_equipment_tank8_eccf445ff5",
		"inventory_revision": state.inventory_revision,
		"price": 2000,
	}
	var rejected: DomainResult = _service.execute(state, command)
	_expect(not rejected.is_ok and rejected.error_code == &"commerce.insufficient_currency",
		"十万金币应买不起二十万的征服者，客户端低价参数不得生效")
	_expect(state.currency == 100000, "被拒绝的交易不得扣款")
	state.currency = 300000
	var bought: DomainResult = _service.execute(state, command)
	_expect(bought.is_ok, "足额资金应能购买征服者战车")
	if not bought.is_ok:
		return
	var candidate: PlayerStateRecord = bought.value.candidate
	_expect(candidate.currency == 100000, "购买必须实际扣除二十万金币")
	var instance_id := ""
	for stack: InventoryStackRecord in candidate.inventory_stacks:
		if stack.item_definition_id == command["definition_id"]:
			instance_id = stack.stack_id
	var sold: DomainResult = _service.execute(candidate, {
		"type": "sell_to_weapon_merchant", "merchant_id": "special_weapon_merchant",
		"instance_id": instance_id, "quantity": 1,
		"inventory_revision": candidate.inventory_revision,
	})
	_expect(sold.is_ok and sold.value.candidate.currency == 200000,
		"在特殊武器商人处回收也应得到十万金币")
	for forbidden_id: String in [
		"glory_equipment_space_collector_2_6e0591d35a",
		"glory_equipment_space_collector_3_dbc34d1181",
		"glory_equipment_space_collector_4_369ba95071",
		"glory_equipment_collector1000_3a487132c5",
		"glory_equipment_space_repair_2_a6f8e7197f",
		"glory_equipment_space_repair_3_1df2183e34",
		"glory_equipment_space_repair_4_0ee1f33f15",
		"glory_equipment_space_repair_5_91446308fd",
	]:
		command["definition_id"] = forbidden_id
		var blocked: DomainResult = _service.execute(state, command)
		_expect(not blocked.is_ok and blocked.error_code == &"commerce.item_not_offered",
			"直接提交购买命令也不得买到本期未上架的工程臂")
	var repair_prices := {
		"glory_equipment_repair_aab7d81665": 500,
		"glory_equipment_repair2_eda809fe71": 5000,
		"glory_equipment_repair3_41cbcf4e1c": 10000,
		"glory_equipment_repair4_488106f12c": 20000,
		"glory_equipment_repair5_728341bcfb": 25000,
		"glory_equipment_repair6_b9eff11a48": 60000,
	}
	for definition_id: String in repair_prices:
		command["definition_id"] = definition_id
		var purchase_result: DomainResult = _service.execute(state, command)
		_expect(purchase_result.is_ok, "地面维修臂必须能通过权威购买：%s" % definition_id)
		if not purchase_result.is_ok:
			continue
		var purchased: PlayerStateRecord = purchase_result.value.candidate
		_expect(purchased.currency == state.currency - int(repair_prices[definition_id]),
			"地面维修臂应按原始售价扣款")
		var found := false
		for stack: InventoryStackRecord in purchased.inventory_stacks:
			if stack.item_definition_id == definition_id:
				found = true
		_expect(found, "购买结果应把正确的地面维修臂加入背包")


## 把窗口命令同步交给真实权威服务并回灌最新面板快照。
## [param command] 窗口发出的交易或任务意图。
## [param manager] 接收权威组合数据的窗口管理器。
func _dispatch(command: Dictionary, manager: GameWindowManager) -> void:
	var result: DomainResult = _service.execute(_state, command)
	if not result.is_ok:
		failures.append("商店命令被拒绝：%s" % result.error_message)
		return
	_state = result.value.candidate
	manager.apply_bundle(result.value.panel_bundle)


## 记录一条测试断言。
## [param condition] 条件是否成立。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 释放测试窗口并输出测试结果。
## [param manager] 本次测试创建的窗口管理器。
func _finish(manager: Control) -> void:
	if failures.is_empty():
		print("WEAPON_MERCHANT_RUNTIME_OK (%d assertions)" % assertions)
		if manager != null:
			manager.free()
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	if manager != null:
		manager.free()
	quit(1)
