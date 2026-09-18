extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
var failures: Array[String] = []
var commands: Array[Dictionary] = []
var service := AuthoritativeCommerceService.new()
var state: PlayerStateRecord
var manager: GameWindowManager


## 延迟创建真实窗口并驱动权威购买回包。
func _initialize() -> void:
	call_deferred("_run")


## 验证分类、确认购买、余额刷新与实际槽位渲染，可按参数保存视觉截图。
func _run() -> void:
	root.size = Vector2i(1400, 820)
	var fixture := Fixture.new()
	fixture.initialize()
	state = fixture._state
	state.amethyst = 20000
	service.initialize()
	manager = GameWindowManager.new()
	root.add_child(manager)
	manager.configure(PlayerPanelSession.new(_dispatch))
	manager.toggle("premium_shop")
	var shop: PremiumShopPanel = manager.navigation_windows.premium_shop
	shop.position = Vector2(660, 20)
	await process_frame
	for child: Node in shop.confirmation.get_children():
		if child is Label:
			_expect(shop.confirmation.get_global_rect().encloses(child.get_global_rect()),
				"16px进入提示在确认框内换行，不因最小宽度溢出")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/premium-shop-entry.png")
	shop._confirm_entry()
	await process_frame
	_expect(shop.search_input.get_theme_font_size("font_size") == 16
		and shop.subcategories.get_theme_font_size("font_size") == 16
		and shop._buy_button.get_theme_font_size("font_size") == 16
		and shop.empty_label.get_theme_font_size("font_size") == 16
		and shop._detail_label.get_theme_font_size("normal_font_size") == 16,
		"商城搜索、分类、购买、空状态及详情统一16px")
	_expect(shop.listing.item_count == 9, "默认显示九件接合器")
	shop._select_subcategory(1)
	_expect(shop.listing.item_count == 4, "新式分类包含四件")
	shop._select_subcategory(2)
	_expect(shop.listing.item_count == 5, "旧式分类包含五件")
	shop._select_subcategory(0)
	shop.listing.select(0)
	shop._select_offer(0)
	shop._request_purchase()
	_expect(shop._purchase_dialog.visible, "购买前显示具体商品确认")
	shop._purchase_dialog.hide()
	shop._confirm_purchase()
	_expect(state.amethyst == 19000 and shop._balance_label.text.contains("19000"), "实际购买回包刷新余额")
	_expect(commands.back().type == "buy_premium_item" and not commands.back().has("price"), "UI不提交可信价格")
	shop._select_offer(0)
	_expect(shop._detail_label.text.contains("1800 紫晶"), "接合器详情显示权威升级材料预算")
	await process_frame
	await process_frame
	_expect(shop._detail_panel.get_global_rect().encloses(shop._detail_label.get_global_rect()),
		"长商品详情完整位于侧栏内部")
	_expect(shop._detail_label.get_global_rect().end.y <= shop._buy_button.global_position.y,
		"滚动详情不覆盖购买按钮")
	_expect(shop._detail_label.get_content_height() > shop._detail_label.size.y
		and shop._detail_label.scroll_active, "完整升级说明通过内部滚动查看")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/premium-shop-detail.png")
	shop._select_subcategory(3)
	_expect(shop.listing.item_count == 7, "接合器升级材料分类显示七种材料")
	shop.listing.select(0)
	shop._select_offer(0)
	shop._quantity.value = 3
	_expect(shop._price_label.text.replace("\n", "").contains("合计：900 紫晶") and not shop._buy_button.disabled, "批量选择更新材料总价")
	shop._request_purchase()
	_expect(shop._purchase_dialog.dialog_text.contains("×3") and shop._purchase_dialog.dialog_text.contains("900"), "确认框明确材料数量与总价")
	shop._purchase_dialog.hide()
	shop._confirm_purchase()
	_expect(state.amethyst == 18100 and int(commands.back().quantity) == 3, "真实材料批量购买回包更新余额")
	shop._select_category(0)
	shop._select_subcategory(2)
	_expect(shop.listing.item_count == 7, "功能道具的升级类也能找到相同材料")
	shop.listing.select(0)
	shop._select_offer(0)
	shop._quantity.value = 99
	_expect(shop._buy_button.disabled, "批量总价超过余额时禁止提交")
	shop._quantity.value = 3
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/premium-upgrade-materials.png")
		shop._select_category(2)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/premium-shop-empty.png")
	var catalog := ItemCatalog.new()
	catalog.initialize()
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(state).value
	var classes := ["HuoLiJieHeQi", "ShengMingJieHeQi", "NewGunJoint", "NewLifeJoint", "gaoregun", "fushigun"]
	for source_class: String in classes:
		for definition_id: String in catalog.definition_ids():
			if catalog.definition(definition_id).get("source_class", "") != source_class:
				continue
			var item: VehicleEquipment = catalog.create(definition_id, {"instance_id": "ui." + source_class, "quantity": 1}).value
			player.receive_loot(item)
			var equipped := player.equip_vehicle_item(item.instance_id, item.equipment_location,
				player.inventory.revision, player.vehicle.loadout.revision)
			_expect(equipped.is_ok, "六件装置可以同时安装")
			break
	for location in [19, 24, 28]:
		for definition_id: String in catalog.definition_ids():
			if int(catalog.definition(definition_id).get("equipment_location", -1)) != location:
				continue
			var item: VehicleEquipment = catalog.create(definition_id, {"instance_id": "special.%d" % location}).value
			player.vehicle.loadout.restore(item)
			break
	manager.panel_session.apply_bundle(PlayerPanelProjector.new(catalog).build_bundle(player))
	manager.vehicle_panel.position = Vector2(25, 20)
	manager.vehicle_panel.show()
	await process_frame
	for location in [16, 17, 32, 33, 14, 34]:
		var found := false
		for child in manager.vehicle_panel._slot_root.get_children():
			if child.name.begins_with("Location_%d_" % location):
				found = true
		_expect(found, "装置槽 %d 必须渲染真实素材" % location)
	var special_count := 0
	for child in manager.vehicle_panel._special_panel._items_root.get_children():
		if String(child.name).begins_with("SpecialLocation_"):
			special_count += 1
	_expect(special_count == 2, "已接通的晶源体与奥斯格兰在独立装备区显示；撒玛尚未开放")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/premium-and-attachments.png")
		manager.vehicle_panel._special_panel.show()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/special-equipment-panel.png")
	manager.queue_free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	print("PREMIUM_UI failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


## 使用真实服务响应会话意图，隔离在测试存档中。
## [param command] 窗口发出的语义命令。
func _dispatch(command: Dictionary) -> void:
	commands.append(command.duplicate(true))
	var result := service.execute(state, command)
	if not result.is_ok:
		failures.append("交易失败: " + result.error_message)
		return
	if result.value.changed:
		state = result.value.candidate
	manager.panel_session.apply_bundle(result.value.panel_bundle)


## 记录真实窗口交互断言。
## [param condition] 验证条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
