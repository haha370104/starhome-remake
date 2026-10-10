extends "res://tests/ui/runtime/player_changes_runtime_test.gd"

const ARMOR_ID := "glory_equipment_frontarmor2_944a84ebc9"
const ARMOR_NAME := "密度金属前护甲"


func _run() -> void:
	Engine.max_fps = 60
	if not await _test_armor_name(): return
	print("FRONT_ARMOR_NAME_RUNTIME checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _test_armor_name() -> bool:
	if not await _boot("res://data/maps/glory_nft_bl_d04.json"): return false
	server.set_process(false)
	_grant(ARMOR_ID, "armor.name.fixture")
	await _sync()
	var armor := player.inventory.find("armor.name.fixture")
	_check(armor != null and armor.display_name == ARMOR_NAME, "原装备身份加载正确名称")
	_check(armor.description == "采用密度金属打造成的护甲，具有一定的防护力。", "描述保持不变")
	_check(armor is Equipment and (armor as Equipment).max_durability == 660, "装备耐久属性保持不变")
	_check(panels.current_player.inventory.find(armor.instance_id).display_name == ARMOR_NAME, "背包协议同步正确名称")
	var known := JsonConfigLoader.load_dictionary("res://data/content/known_items_v1.json")
	_check(known.is_ok, "已知内容登记目录加载")
	var registration_found := false
	for registration: Dictionary in known.value.definitions:
		if registration.id == "item:equipment:frontarmor2:c935dcb2c8":
			registration_found = true
			_check(registration.display_name == ARMOR_NAME, "原登记身份及名称正确")
	_check(registration_found, "原装备登记身份仍存在")
	var merchant := WeaponMerchantCatalog.new()
	_check(merchant.initialize(server.player_panel_service.catalog).is_ok, "商店目录加载")
	_check(merchant.offer(ARMOR_ID).is_empty(), "名称修复不改变武器商人的原销售范围")
	var rules := JsonConfigLoader.load_dictionary("res://data/gameplay/equipment_maintenance_rules_v1.json")
	_check(rules.is_ok, "维护规则目录加载")
	var maintenance_found := false
	for profile: Dictionary in rules.value.equipment:
		if profile.definition_id == ARMOR_ID:
			maintenance_found = true
			_check(profile.display_name == ARMOR_NAME and not profile.regular_allowed, "维护名称正确，原维修准入规则不变")
	_check(maintenance_found, "原维护规则身份仍存在")
	windows.inventory_panel.show()
	await process_frame
	var view: InventoryItemView = windows.inventory_panel._item_canvas._views[armor.instance_id]
	view.mouse_entered.emit()
	await create_timer(0.11).timeout
	var tooltip := ItemHoverHighlight.active_tooltip() as LegacyItemTooltip
	_check(tooltip != null and tooltip.visible and tooltip._title_label.text.begins_with(ARMOR_NAME), "真实背包悬停显示正式名称")
	ItemHoverHighlight.dismiss_for(view)
	_check((await _send({"type": "equip_vehicle_item", "instance_id": armor.instance_id, "location": 5})).get("ok", false), "通过正式命令装配前护甲")
	await process_frame
	_check(player.vehicle.loadout.at(5).display_name == ARMOR_NAME, "服务端装备名称正确")
	_check(panels.current_player.vehicle.loadout.at(5).display_name == ARMOR_NAME, "客户端装备槽同步正确名称")
	var title_found := false
	for visual: Control in windows.vehicle_panel._slot_root.get_children():
		if visual.is_queued_for_deletion(): continue
		visual.mouse_entered.emit()
		await create_timer(0.11).timeout
		tooltip = ItemHoverHighlight.active_tooltip() as LegacyItemTooltip
		if tooltip != null and tooltip._title_label.text.begins_with(ARMOR_NAME): title_found = true
		ItemHoverHighlight.dismiss_for(visual)
	_check(title_found, "战车面板悬停使用正式名称")
	_save_and_compare()
	var store_path := config.player_state_store_path
	await _close()
	if not await _boot("res://data/maps/glory_nft_bl_d04.json", store_path): return false
	_check(player.vehicle.loadout.at(5).definition_id == ARMOR_ID and player.vehicle.loadout.at(5).display_name == ARMOR_NAME, "原存档身份重载后名称正确")
	_check(panels.current_player.vehicle.loadout.at(5).display_name == ARMOR_NAME, "重启后客户端名称正确")
	await _close()
	return true
