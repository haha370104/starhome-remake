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


func _dispatch(command: Dictionary, manager: GameWindowManager) -> void:
	var result: DomainResult = _service.execute(_state, command)
	if not result.is_ok:
		failures.append("商店命令被拒绝：%s" % result.error_message)
		return
	_state = result.value.candidate
	manager.apply_bundle(result.value.panel_bundle)


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


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
