extends "res://tests/ui/runtime/player_changes_runtime_test.gd"

const IRON_ID := "iron"
const IRON_DESCRIPTION := "金属块，打造与合成的原材料之一。"
const FACTORY_MAP := "res://assets/glory/map_definitions/glory_nft_bl_factory1.json"


func _run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280, 720)
	if not await _boot(FACTORY_MAP): return
	print("IRON_MATERIAL_RUNTIME stage=production")
	_grant(IRON_ID, "iron.fixture", 2)
	await _sync()
	await _manufacturing()
	print("IRON_MATERIAL_RUNTIME stage=inventory")
	await _check_iron_inventory()
	_save_and_compare()
	var store_path := config.player_state_store_path
	var quantity := player.inventory.count_definition(IRON_ID)
	await _close()
	if not await _boot(FACTORY_MAP, store_path): return
	_check(player.inventory.count_definition(IRON_ID) == quantity, "重启保留铁的原有身份和数量")
	await _check_iron_inventory()
	await _close()
	print("IRON_MATERIAL_RUNTIME checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check_iron_inventory() -> void:
	var iron := player.inventory.find("iron.fixture")
	_check(iron != null, "原有铁实例仍存在")
	if iron == null: return
	_check(iron.definition_id == IRON_ID and iron.display_name == "铁", "铁与铁矿保持不同物品身份")
	_check(iron.description == IRON_DESCRIPTION, "服务端使用原版铁块描述")
	_check(iron.max_stack == 99, "修复不改变堆叠限制")
	_check(panels.current_player.inventory.find(iron.instance_id).description == IRON_DESCRIPTION, "客户端恢复原版描述")
	_check(server.player_panel_service.catalog.create("iron_ore", {}).value.display_name == "铁矿", "不改变铁矿定义")
	_consistent("铁块")
	windows.inventory_panel.show()
	await process_frame
	var canvas: InventoryCanvas = windows.inventory_panel._item_canvas
	_check(canvas._views.has(iron.instance_id), "真实背包创建铁块视图")
	if not canvas._views.has(iron.instance_id): return
	var view: InventoryItemView = canvas._views[iron.instance_id]
	var deadline := Time.get_ticks_msec() + 10000
	while view._icon.texture == null and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(view._icon.texture != null, "真实背包加载铁块图标")
	if view._icon.texture != null:
		var image := view._icon.texture.get_image()
		_check(image.get_size() == Vector2i(45, 26), "图标使用原始尺寸")
		_check(image.get_used_rect().has_area(), "图标含可见像素")
	view.mouse_entered.emit()
	await create_timer(0.11).timeout
	var tooltip := ItemHoverHighlight._active_tooltip
	_check(tooltip != null and tooltip.visible, "真实悬停说明已显示")
	if tooltip != null:
		_check(tooltip.get_node("Content/Body").text == IRON_DESCRIPTION, "背包悬停显示正确铁块描述")
	if "--capture-iron" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		print("IRON_MATERIAL_RUNTIME stage=capture")
		RenderingServer.force_draw(false)
		_check(root.get_texture().get_image().save_png("res://.godot/iron-inventory.png") == OK, "保存渲染背包截图")
	ItemHoverHighlight.dismiss_for(view)
