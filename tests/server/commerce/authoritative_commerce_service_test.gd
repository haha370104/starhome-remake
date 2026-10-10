extends SceneTree

const PanelFixtureScript := preload("res://tests/fixtures/player_panel_service_fixture.gd")
const CommerceServiceScript := preload(
	"res://scripts/server/commerce/authoritative_commerce_service.gd"
)

var failures := PackedStringArray()
var assertions := 0


## 验证权威商店查询、买卖和循环任务事务。
func _initialize() -> void:
	var fixture = PanelFixtureScript.new()
	var fixture_loaded: DomainResult = fixture.initialize()
	var service = CommerceServiceScript.new()
	var service_loaded: DomainResult = service.initialize()
	_expect(fixture_loaded.is_ok and service_loaded.is_ok, "权威交易夹具应初始化")
	if not fixture_loaded.is_ok or not service_loaded.is_ok:
		_finish()
		return
	var player_result: DomainResult = fixture.current_player()
	_expect(player_result.is_ok, "夹具应还原为权威 Player 聚合")
	if not player_result.is_ok:
		_finish()
		return
	var state: Player = player_result.value
	state.map_id = "glory_nft_bl_weaponshop1"
	state.inventory.currency = 100000
	var queried: DomainResult = service.execute(state, {"type": "query_weapon_merchant"})
	_expect(queried.is_ok and queried.value.panel_bundle.has("commerce"), "查询应返回交易快照")
	_expect(queried.value.panel_bundle.commerce.operation.action == "query",
		"交易快照应携带本次操作结果供原版消息窗反馈")
	_expect(queried.value.panel_bundle.commerce.has("sell_prices"),
		"查询只返回静态出售价，不复制玩家的动态卖品列表")
	var pre_buy := state
	var original_shirt: GameItem = state.inventory.find("inventory.training_shirt")
	var bought: DomainResult = service.execute(state, {
		"type": "buy_from_weapon_merchant",
		"definition_id": "glory_equipment_gun1_216568dc50",
		"inventory_revision": state.inventory.revision,
	})
	_expect(bought.is_ok, "余额和背包空间足够时应能购买新兵能量炮")
	if bought.is_ok:
		_expect(bought.value.operation.action == "buy" and not bought.value.has("panel_bundle"),
			"购买事务只返回操作结果，不重建交易面板")
		state = bought.value.candidate
		_expect(state.inventory.currency == 99500, "新兵能量炮应按原版500金币售价扣款")
		_expect(state.inventory != pre_buy.inventory \
			and state.inventory.find(original_shirt.instance_id) == original_shirt,
			"购买只复制背包容器并共享未受影响的物品")
	var pre_sell := state
	var unrelated_item: GameItem = state.inventory.items()[0]
	var sold: DomainResult = service.execute(state, {
		"type": "sell_to_weapon_merchant",
		"instance_id": "inventory.training_shirt",
		"quantity": 1,
		"inventory_revision": state.inventory.revision,
	})
	_expect(sold.is_ok, "武器商人应允许按出售价出售背包中的绑定服装")
	if sold.is_ok:
		_expect(not sold.value.has("panel_bundle"), "出售事务不重建卖品展示 DTO")
		_expect(pre_sell.inventory.find("inventory.training_shirt") != null \
			and sold.value.candidate.inventory.find("inventory.training_shirt") == null,
			"出售只改候选，不污染原玩家背包")
		_expect(sold.value.candidate.inventory.find(unrelated_item.instance_id) == unrelated_item,
			"出售复用未修改的背包物品")
		state = sold.value.candidate
	var accepted: DomainResult = service.execute(state, {"type": "accept_weapon_merchant_task"})
	_expect(accepted.is_ok, "武器商人循环任务应可领取")
	if accepted.is_ok:
		state = accepted.value.candidate
		_expect(bool(state.quest_states.arms_npc_supply.accepted), "任务状态应进入持久化 DTO")
	var missing: DomainResult = service.execute(state, {
		"type": "turn_in_weapon_merchant_task",
		"inventory_revision": state.inventory.revision,
	})
	_expect(not missing.is_ok and missing.error_code == &"quest.requirements_missing", "材料不足时服务器应拒绝交付")
	var recorded: DomainResult = fixture._mapper.to_record(state)
	var round_trip: DomainResult = PlayerStateRecord.from_dictionary(recorded.value.to_dictionary()) \
		if recorded.is_ok else recorded
	_expect(round_trip.is_ok and bool(round_trip.value.quest_states.arms_npc_supply.accepted), "任务状态应可序列化往返")
	if OS.get_cmdline_user_args().has("--benchmark"):
		_benchmark_trade_path(fixture, service)
	_finish()


func _benchmark_trade_path(fixture: PlayerPanelServiceFixture, service: AuthoritativeCommerceService) -> void:
	var player_result: DomainResult = fixture.current_player()
	if not player_result.is_ok:
		push_error("商人基准夹具还原失败")
		return
	var player: Player = player_result.value
	player.map_id = "glory_nft_bl_weaponshop1"
	player.inventory.currency = 100000000
	var shirt: GameItem = player.inventory.find("inventory.training_shirt")
	for index in range(player.inventory.capacity - player.inventory.items().size()):
		var added := player.inventory.add_reward(shirt.copy_stack("benchmark.shirt.%d" % index, 1))
		if not added.is_ok:
			push_error("无法构造满背包商人基准：%s" % added.error_message)
			return
	var sell_samples := _measure_trade(service, fixture._service, player, "sell_to_weapon_merchant")
	var buy_player_result: DomainResult = fixture.current_player()
	var buy_player: Player = buy_player_result.value
	buy_player.map_id = player.map_id
	buy_player.inventory.currency = 100000000
	var buy_samples := _measure_trade(service, fixture._service, buy_player, "buy_from_weapon_merchant")
	for phase: String in ["total", "execute", "change"]:
		_print_samples("sell %s rows=%d" % [phase, player.inventory.items().size()], sell_samples[phase])
		_print_samples("buy %s rows=%d" % [phase, buy_player.inventory.items().size()], buy_samples[phase])


func _measure_trade(
	service: AuthoritativeCommerceService,
	panel_service: AuthoritativePlayerPanelService,
	player: Player,
	command_type: String,
) -> Dictionary:
	var samples := {"total": [], "execute": [], "change": []}
	var instance_id := "inventory.training_shirt" if command_type == "sell_to_weapon_merchant" else ""
	for iteration in range(210):
		var started_at := Time.get_ticks_usec()
		var result: DomainResult = service.execute(player, {
			"type": command_type,
			"definition_id": "glory_equipment_gun1_216568dc50",
			"instance_id": instance_id,
			"quantity": 1,
			"inventory_revision": player.inventory.revision,
		})
		if not result.is_ok:
			push_error("商人基准事务失败：%s" % result.error_message)
			return {"total": [], "execute": [], "change": []}
		var executed_at := Time.get_ticks_usec()
		panel_service.changes(player, result.value.candidate)
		var finished_at := Time.get_ticks_usec()
		if iteration >= 10:
			samples.total.append(finished_at - started_at)
			samples.execute.append(executed_at - started_at)
			samples.change.append(finished_at - executed_at)
	return samples


func _print_samples(label: String, samples: Array) -> void:
	if samples.is_empty():
		return
	samples.sort()
	var total := 0
	for sample: int in samples:
		total += sample
	print("MERCHANT_BENCHMARK %s samples=%d mean_us=%.1f p50_us=%d p95_us=%d max_us=%d" % [
		label, samples.size(), float(total) / samples.size(),
		samples[int(samples.size() * 0.50)], samples[int(samples.size() * 0.95)], samples[-1],
	])


## 记录一条测试断言。
## [param condition] 条件是否成立。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出测试结果并结束进程。
func _finish() -> void:
	if failures.is_empty():
		print("AUTHORITATIVE_COMMERCE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
