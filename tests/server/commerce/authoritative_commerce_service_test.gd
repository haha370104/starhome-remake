extends SceneTree

const PanelFixtureScript := preload("res://tests/fixtures/player_panel_service_fixture.gd")
const CommerceServiceScript := preload(
	"res://scripts/server/commerce/authoritative_commerce_service.gd"
)

var failures := PackedStringArray()
var assertions := 0


func _initialize() -> void:
	var fixture = PanelFixtureScript.new()
	var fixture_loaded: DomainResult = fixture.initialize()
	var service = CommerceServiceScript.new()
	var service_loaded: DomainResult = service.initialize()
	_expect(fixture_loaded.is_ok and service_loaded.is_ok, "权威交易夹具应初始化")
	if not fixture_loaded.is_ok or not service_loaded.is_ok:
		_finish()
		return
	var state: PlayerStateRecord = fixture._state
	state.currency = 100000
	var queried: DomainResult = service.execute(state, {"type": "query_weapon_merchant"})
	_expect(queried.is_ok and queried.value.panel_bundle.has("commerce"), "查询应返回交易快照")
	_expect(queried.value.panel_bundle.commerce.operation.action == "query",
		"交易快照应携带本次操作结果供原版消息窗反馈")
	var bought: DomainResult = service.execute(state, {
		"type": "buy_from_weapon_merchant",
		"definition_id": "glory_equipment_gun1_216568dc50",
		"inventory_revision": state.inventory_revision,
	})
	_expect(bought.is_ok, "余额和背包空间足够时应能购买新兵能量炮")
	if bought.is_ok:
		_expect(bought.value.panel_bundle.commerce.operation.action == "buy",
			"购买回包应标明成功动作")
		state = bought.value.candidate
		_expect(state.currency == 99500, "新兵能量炮应按原版500金币售价扣款")
	var sold: DomainResult = service.execute(state, {
		"type": "sell_to_weapon_merchant",
		"instance_id": "inventory.training_shirt",
		"quantity": 1,
		"inventory_revision": state.inventory_revision,
	})
	_expect(sold.is_ok, "武器商人应收购背包中的绑定服装")
	if sold.is_ok:
		state = sold.value.candidate
	var accepted: DomainResult = service.execute(state, {"type": "accept_weapon_merchant_task"})
	_expect(accepted.is_ok, "武器商人循环任务应可领取")
	if accepted.is_ok:
		state = accepted.value.candidate
		_expect(bool(state.quest_states.arms_npc_supply.accepted), "任务状态应进入持久化 DTO")
	var missing: DomainResult = service.execute(state, {
		"type": "turn_in_weapon_merchant_task",
		"inventory_revision": state.inventory_revision,
	})
	_expect(not missing.is_ok and missing.error_code == &"quest.requirements_missing", "材料不足时服务器应拒绝交付")
	var round_trip: DomainResult = PlayerStateRecord.from_dictionary(state.to_dictionary())
	_expect(round_trip.is_ok and bool(round_trip.value.quest_states.arms_npc_supply.accepted), "任务状态应可序列化往返")
	_finish()


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("AUTHORITATIVE_COMMERCE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
