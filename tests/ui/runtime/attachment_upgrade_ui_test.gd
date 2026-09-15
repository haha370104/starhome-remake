extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
var service := AuthoritativeCommerceService.new()
var state: PlayerStateRecord
var manager: GameWindowManager
var failures: Array[String] = []
var sent: Array[Dictionary] = []


## 场景可用后从真实商城入口操作强化窗口。
func _initialize() -> void:
	call_deferred("_run")


## 验证材料预览、确认、同实例连续升级、缺料提示及当前玩家属性同步。
func _run() -> void:
	root.size = Vector2i(1280, 800)
	var fixture := Fixture.new()
	fixture.initialize()
	service.initialize()
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory.restore_items([])
	var shop := PremiumShopService.new()
	shop.initialize(items)
	var id := "glory_equipment_newgunjoint_01c76b26fe"
	var plan := shop.upgrade_pricing().plan_for(id, 0)
	player.receive_loot(items.create(id, {"instance_id": "ui-upgrade"}).value)
	player.equip_vehicle_item("ui-upgrade", 32, player.inventory.revision, player.vehicle.loadout.revision)
	for requirement: Dictionary in plan.requirements:
		player.receive_loot(items.create(requirement.definition_id, {"instance_id": requirement.definition_id, "quantity": requirement.quantity}).value)
	state = mapper.to_record(player).value
	manager = GameWindowManager.new()
	root.add_child(manager)
	manager.configure(PlayerPanelSession.new(_dispatch))
	var shop_panel: PremiumShopPanel = manager.navigation_windows.premium_shop
	var entry: Button
	for button: Node in shop_panel.find_children("*", "Button", true, false):
		if button.text == "接合器强化":
			entry = button
	_expect(entry != null, "商城提供真实强化入口")
	entry.pressed.emit()
	var window: AttachmentUpgradePanel = manager.navigation_windows.attachment_upgrades
	window.position = Vector2(80, 90)
	_expect(window.visible and window.listing.item_count == 1, "入口查询自有已装配接合器")
	window.listing.select(0)
	window._select(0)
	_expect(window._icon.texture != null, "强化窗口加载装备背包表现而非整套模式字典")
	_expect(not window.upgrade_button.disabled and window.details.text.contains("冲击晶体：6 / 6"), "完整展示真实配方数量及可执行状态")
	window.upgrade_button.pressed.emit()
	_expect(window.confirmation.visible and window.confirmation.dialog_text.contains("+0 → +1")
		and window.confirmation.dialog_text.contains("冲击晶体 ×6"), "二次确认显示实际单级消耗")
	var before := state.to_dictionary()
	window.confirmation.get_cancel_button().pressed.emit()
	window.confirmation.hide()
	_expect(state.to_dictionary() == before and sent.back().type == "query_attachment_upgrades", "取消确认不提交交易")
	window.upgrade_button.pressed.emit()
	window.confirmation.confirmed.emit()
	window.confirmation.hide()
	_expect(sent.back().type == "upgrade_attachment" and not sent.back().has("target_level"), "只发送实例及版本，不指定目标等级")
	_expect(manager.panel_session.current_player.attachment_item("ui-upgrade").upgrade_level == 1, "同一权威回包同步当前玩家强化等级")
	_expect(window.listing.get_item_text(0).contains("+1") and window.upgrade_button.disabled and window.details.text.contains("材料不足"), "成功后保留实例选择并显示下一级缺料")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/attachment-upgrade-panel.png")
	manager.queue_free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	print("ATTACHMENT_UPGRADE_UI failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


## 提交真实服务操作，只接受成功候选并派发统一回包。
## [param command] UI纯意图。
func _dispatch(command: Dictionary) -> void:
	sent.append(command.duplicate(true))
	var result := service.execute(state, command)
	if not result.is_ok:
		failures.append(result.error_message)
		return
	if result.value.changed:
		state = result.value.candidate
	manager.panel_session.apply_bundle(result.value.panel_bundle)


## 记录交互失败。
## [param condition] 交互结果。
## [param message] 失败原因。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
