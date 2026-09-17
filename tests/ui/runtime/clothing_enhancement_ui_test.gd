extends SceneTree

var failures: Array[String] = []
var checks := 0
var service := AuthoritativeCommerceService.new()
var state: PlayerStateRecord
var manager: GameWindowManager
var mapper: PlayerStateMapper
var items := ItemCatalog.new()
var sent: Array[Dictionary] = []


## 初始化完整窗口管理器并连接内存中的权威服务。
func _initialize() -> void:
	call_deferred("_run")


## 验证人物入口、材料选择、消费确认、连续镶嵌、合成与迁移。
func _run() -> void:
	root.size = Vector2i(1120, 760)
	items.initialize()
	service.initialize()
	mapper = PlayerStateMapper.new(items)
	var fixture := PlayerPanelServiceFixture.new()
	fixture.initialize()
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory.currency = 100000
	player.equip_character_item("inventory.training_shirt", "upper_body", player.inventory.revision, player.revision)
	player.receive_loot(items.create("male_sleeveless_shirt", {"instance_id": "target"}).value)
	for prefix: String in ClothingEnhancement.PREFIXES:
		for rank: int in [1, 4]:
			_give(player, "enhancement:prefix:%s:%d" % [prefix, rank], 3)
	_give(player, "enhancement:trait:economy:4", 3)
	_give(player, "enhancement:gem:movement_speed:3", 8)
	_give(player, "enhancement:gem:max_health:5", 2)
	state = mapper.to_record(player).value
	manager = GameWindowManager.new()
	root.add_child(manager)
	manager.configure(PlayerPanelSession.new(_dispatch, items))
	manager.panel_session.apply_bundle(service.build_bundle(state))
	_expect(manager.character_panel.get_node_or_null("Content/ClothingEnhancementButton") != null, "人物面板存在强化按钮")
	manager.character_panel.enhancement_requested.emit()
	var panel: ClothingEnhancementPanel = manager.navigation_windows.clothing_enhancement
	panel.position = Vector2(90, 60)
	_expect(panel.visible and panel.clothes_list.item_count == 2 and panel.stones_list.item_count == 11, "人物入口加载两件服装与真实材料")
	panel.focus_item("inventory.training_shirt", false)
	panel.focus_item("enhancement:prefix:tiger:4", true)
	_expect(not panel.enhance_button.disabled and panel.details.get_parsed_text().contains("战车生命 +10%"), "前缀材料显示收益和代价")
	panel.enhance_button.pressed.emit()
	var before := state.to_dictionary()
	panel.confirmation.hide()
	_expect(before == state.to_dictionary(), "取消确认不扣材料")
	panel.enhance_button.pressed.emit()
	panel.confirmation.confirmed.emit()
	panel.confirmation.hide()
	_expect(PlayerEnhancementActions.clothing(manager.panel_session.current_player, "inventory.training_shirt").enhancement.prefix_quality == 4, "刻印同步穿着装备")
	panel.focus_item("enhancement:gem:movement_speed:3", true)
	_expect(panel.details.get_parsed_text().contains("多余等级不会保留"), "高级宝石打低段有明确提示")
	for _index: int in range(2):
		panel.enhance_button.pressed.emit()
		panel.confirmation.confirmed.emit()
		panel.confirmation.hide()
	_expect(PlayerEnhancementActions.clothing(manager.panel_session.current_player, "inventory.training_shirt").enhancement.gem_stage == 2, "每次仅增加一段")
	panel.synthesize_button.pressed.emit()
	_expect(panel.confirmation.dialog_text.contains("×2"), "宝石合成为二合一")
	panel.confirmation.confirmed.emit()
	panel.confirmation.hide()
	var decoded: Player = mapper.to_domain(state).value
	_expect(decoded.inventory.count_definition("enhancement:gem:movement_speed:4") == 1, "实际产出下一级宝石")
	panel.transfer_target.select(1)
	panel._request_transfer()
	panel.confirmation.confirmed.emit()
	panel.confirmation.hide()
	decoded = mapper.to_domain(state).value
	_expect(PlayerEnhancementActions.clothing(decoded, "target").enhancement.gem_stage == 2 and PlayerEnhancementActions.clothing(decoded, "inventory.training_shirt").enhancement.gem_stage == 0, "迁移一次且来源清空")
	panel.focus_item("target", false)
	panel.reset_button.pressed.emit()
	_expect(panel.confirmation.dialog_text.contains("不返还"), "重置明确说明不返还")
	panel.confirmation.confirmed.emit()
	panel.confirmation.hide()
	decoded = mapper.to_domain(state).value
	_expect(PlayerEnhancementActions.clothing(decoded, "target").enhancement.gem_stage == 0, "重置清空实际路线")
	panel.focus_item("inventory.training_shirt", false)
	panel.focus_item("enhancement:trait:economy:4", true)
	var menu := manager.inventory_panel.context_menu
	menu.open_for(decoded.inventory.find("enhancement:gem:max_health:5"), decoded.inventory.revision, Vector2(20, 20))
	_expect(menu._actions.has("clothing_enhancement"), "强化石右键提供入口")
	menu.dismiss()
	var view := InventoryItemView.new()
	view.configure(decoded.inventory.find("enhancement:gem:max_health:5"), Vector2(50, 45))
	_expect(view.get_node("GemLevelBadge").text == "L5", "图标显示宝石等级")
	view.free()
	_expect(panel.details.get_rect().end.x <= panel.size.x - 20 and panel.stones_list.size.y <= 400, "详情位于固定侧栏并允许滚动")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/clothing-enhancement-panel.png")
	manager.queue_free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	print("CLOTHING_ENHANCEMENT_UI checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 添加真实定义材料，不接触本地玩家存档。
## [param player] 隔离玩家。
## [param definition] 材料身份。
## [param count] 数量。
func _give(player: Player, definition: String, count: int) -> void:
	player.receive_loot(items.create(definition, {"instance_id": definition, "quantity": count}).value)


## 把 UI 意图交给真实权威服务并应用同事务回包。
## [param command] 当前面板纯意图。
func _dispatch(command: Dictionary) -> void:
	sent.append(command.duplicate(true))
	var result := service.execute(state, command)
	if not result.is_ok:
		failures.append(result.error_message)
		return
	if result.value.changed:
		state = result.value.candidate
	manager.panel_session.apply_bundle(result.value.panel_bundle)


## 记录行为检查。
## [param condition] 实际检查结果。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
