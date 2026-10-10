extends SceneTree

class RejectingSave extends PlayerStateRepository:
	## 模拟磁盘拒绝；不能把失败当作退出成功。
	## [param _state] 隔离存档。[param _revision] 当前仓储版本。
	func save_player_durable(_state: PlayerStateRecord, _revision: int) -> DomainResult:
		return DomainResult.failure(&"test.save_failed", "验证保存失败")

# 使用真实主场景、进程内传输和隔离存档；不以直接调用服务绕过消息与窗口。
var hall: Node
var server: AuthoritativeServer
var network: ClientMultiplayerSession
var panels: PlayerPanelSession
var windows: GameWindowManager
var player: Player
var config: DedicatedServerConfig
var checks := 0
var failures: Array[String] = []
var messages: Array[Dictionary] = []
var commands: Array[Dictionary] = []
var full_updates := 0
var equipment_updates := 0


## 进入实际场景后逐项验证增量，不使用用户存档。
func _initialize() -> void:
	call_deferred("_run")


## 覆盖背包、换装、方案、食品、采矿和生产的传输及展示边界。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	if not await _boot("res://data/maps/glory_nft_bl_d04.json"): return
	await _inventory_and_presets()
	await _food()
	await _mining()
	_save_and_compare()
	await _restart_mining()
	await _versions()
	_save_and_compare()
	await _close()
	if not await _boot("res://assets/glory/map_definitions/glory_nft_bl_factory1.json"): return
	await _manufacturing()
	_save_and_compare()
	await _exit_and_reload()
	await _close()
	print("PLAYER_CHANGES_RUNTIME checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 注入隔离服务器配置，等待真实地图和角色握手完成。
## [param map_path] 被验证的实际地图定义。返回连接是否就绪。
func _boot(map_path: String, store_path: String = "") -> bool:
	config = DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = map_path
	config.default_spawn = Vector2(1200, 1200) if "d04" in map_path else Vector2(1104, 420)
	config.autosave_interval_seconds = 100000
	config.player_state_store_path = store_path if not store_path.is_empty() else "res://.godot/player-changes-%d.json" % Time.get_ticks_usec()
	hall = load("res://scenes/main_hall.tscn").instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	network = hall.multiplayer_presenter.session
	panels = hall.panel_session
	windows = hall.game_window_manager
	panels.player_changed.connect(func(_player: Player) -> void: full_updates += 1)
	panels.equipment_changed.connect(func(_player: Player) -> void: equipment_updates += 1)
	panels.command_dispatched.connect(func(command: Dictionary) -> void: commands.append(command))
	_check(network.network_adapter.configure_in_process_server(config), "注入隔离配置")
	_check(network.connect_to_server("127.0.0.1") == OK, "连接真实进程内服务器")
	server = network.network_adapter._transport_endpoint.authoritative_server
	server.server_message_generated.connect(func(_peer: int, message: Dictionary) -> void: messages.append(message))
	var deadline := Time.get_ticks_msec() + 60000
	while (not panels.current_player.is_ready() or hall.active_world_controller.definition.map_id != server.map_instance.definition.map_id) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not panels.current_player.is_ready():
		push_error("玩家握手未完成")
		quit(1)
		return false
	player = server.autosave_service.player_for(String(network.local_entity_id))
	await process_frame
	_reset_observations()
	return true


## 新增数据仅用于建立场景；操作和同步验证仍走正式传输。
## [param definition] 目录身份。[param id] 隔离实例身份。[param count] 初始数量。
func _grant(definition: String, id: String, count: int = 1) -> void:
	var granted := server.player_panel_service.receive_loot(player, {"loot_id": id, "item_definition_id": definition, "quantity": count})
	_check(granted.is_ok, "准备物品 " + definition)
	if granted.is_ok: server.autosave_service.commit_player(player.entity_id, player)


## 从客户端当前版本发出正式意图，错误也由传输回包记录。
## [param command] 本次操作。返回本次服务器响应。
func _send(command: Dictionary) -> Dictionary:
	command.merge({"inventory_revision": panels.current_player.inventory.revision,
		"loadout_revision": panels.current_player.vehicle.loadout.revision,
		"state_revision": panels.current_player.revision})
	panels.dispatch(command)
	await process_frame
	await process_frame
	return messages.back().get("result", {}) if not messages.is_empty() else {}


## 显式同步仅用于场景准备和协议恢复，不计入正常操作。
func _sync() -> void:
	await _send({"type": "query"})


## 检查最终客户端库存，而非只检查回包字段存在。
## [param label] 失败时的操作名称。
func _consistent(label: String) -> void:
	var actual := server.player_panel_service.build_bundle(player)
	_check(panels.snapshot_bundle().inventory == actual.inventory, label + "：库存最终值一致")
	_check(panels.current_player.revision == player.revision and not panels._resync_pending, label + "：版本连续")


## 覆盖减少、移除、移动、换装、拒绝及窗口节点复用。
func _inventory_and_presets() -> void:
	_grant("iron_ore", "ore", 12)
	_grant("male_sleeveless_shirt", "shirt")
	await _sync()
	windows.inventory_panel.show()
	await process_frame
	_reset_observations()
	var canvas: InventoryCanvas = windows.inventory_panel._item_canvas
	var original: InventoryItemView = canvas._views.ore
	_check((await _send({"type": "move_inventory_item", "instance_id": "ore", "position_px": [30, 45]})).get("ok", false), "移动背包图标")
	await process_frame
	_check(canvas._views.ore == original and original.position == Vector2(30, 45), "移动复用节点并更新位置")
	_check((await _send({"type": "split_inventory_item", "instance_id": "ore", "quantity": 4})).get("ok", false), "拆堆成功")
	await process_frame
	_consistent("拆堆")
	_check((await _send({"type": "merge_inventory_item", "instance_id": "ore"})).get("ok", false), "合堆成功")
	await process_frame
	_check(player.inventory.find("ore").quantity == 12 and canvas._views.ore == original, "合堆数量及节点复用")
	_check(canvas.get_child_count() == player.inventory.items().size(), "合堆删除失效视图")
	_check(full_updates == 0 and equipment_updates == 0, "背包操作不触发全量或外观刷新")
	var revision := player.revision
	_check(not (await _send({"type": "split_inventory_item", "instance_id": "ore", "quantity": 99})).get("ok", true), "非法拆堆拒绝")
	_check(player.revision == revision and player.inventory.find("ore").quantity == 12, "拒绝保持原状态")
	_check((await _send({"type": "equip_character_item", "instance_id": "shirt", "character_slot": "upper_body"})).get("ok", false), "人物穿衣成功")
	await process_frame
	_check(panels.current_player.character_equipment.at("upper_body").instance_id == "shirt" and not canvas._views.has("shirt"), "装备与背包原子转移")
	_check(equipment_updates == 1 and full_updates == 0, "换装只发外观增量")
	_check((await _send({"type": "unequip_character_item", "character_slot": "upper_body"})).get("ok", false), "卸衣成功")
	await process_frame
	_consistent("卸衣")
	var preset: VehicleLoadoutPresetsPanel = windows.navigation_windows.vehicle_presets
	preset.open_board()
	await process_frame
	await process_frame
	preset.title_edit.text = "验证方案"
	preset.capture_button.pressed.emit()
	await process_frame
	_check(player.vehicle_presets.at(0).name == "验证方案" and not preset.apply_button.disabled, "方案按钮保存并收到增量")
	preset.apply_button.pressed.emit()
	await process_frame
	await process_frame
	_check(preset._awaiting, "方案拒绝后保留等待状态")
	preset._process(5.1)
	await process_frame
	await process_frame
	_check(not preset._awaiting, "请求超时通过组件查询恢复")
	_check((await _send({"type": "unequip_vehicle_item", "location": 3})).get("ok", false), "方案测试卸下推进器")
	preset.apply_button.pressed.emit()
	await process_frame
	await process_frame
	_check(preset._remaining > 0 and not preset._awaiting, "方案应用回包与冷却")
	var count := commands.size()
	preset._process(2.1)
	_check(commands.size() == count, "方案窗口不再两秒轮询")
	preset.hide()
	_consistent("方案应用")


## 通过真实物品使用和食品时钟验证到期、回血与无变化时不发消息。
func _food() -> void:
	for label: String in ["比萨", "龙舌兰酒"]:
		for id: String in server.player_panel_service.catalog.definition_ids():
			if server.player_panel_service.catalog.display_name(id) == label:
				_grant(id, label, 2)
				break
	player.health = 20
	await _sync()
	_reset_observations()
	_check((await _send({"type": "use_inventory_item", "instance_id": "比萨"})).get("ok", false), "食物使用成功")
	_check((await _send({"type": "use_inventory_item", "instance_id": "龙舌兰酒"})).get("ok", false), "回血食物使用成功")
	var now := int(Time.get_unix_time_from_system())
	server._food_runtime.advance(server.sessions.all_sessions(), now + 1)
	server._flush_player_changes()
	await process_frame
	_check(player.health == 30 and panels.current_player.health == 30, "食品回血准确同步")
	_consistent("食品消耗")
	var count := messages.size()
	server._food_runtime.advance(server.sessions.all_sessions(), now + 1)
	server._flush_player_changes()
	_check(messages.size() == count, "同一秒不重复回血或发包")
	server._food_runtime.advance(server.sessions.all_sessions(), now + 3601)
	server._flush_player_changes()
	await process_frame
	_check(player.food_status.active.is_empty() and panels.current_player.food_status.active.is_empty(), "食品到期同步清除")
	_check(full_updates == 0 and equipment_updates == 0, "食品不重建全量玩家或外观")


## 真实采掘意图、周期、任务和满包拒绝共用同一在线玩家。
func _mining() -> void:
	_grant("glory_equipment_collector_ac947ee094", "collector")
	var quests: RepeatableQuestCatalog = server.commerce_service.quests.catalog
	var quest_id := ""
	for id: String in quests.definitions:
		for requirement: Dictionary in quests.definitions[id].get("requirements", []):
			if requirement.display_name == "铁矿": quest_id = id
	if not quest_id.is_empty(): player.quest_states[quest_id] = {"accepted": true, "completions": 0}
	await _sync()
	_check((await _send({"type": "equip_vehicle_item", "instance_id": "collector", "location": 1})).get("ok", false), "装配采掘臂")
	await process_frame
	var map := server.map_instance
	var source: MineSource = map.mining_module.sources.values()[0]
	var entity: AuthoritativeEntity = map.entities[player.entity_id]
	entity.position = source.position + Vector2(40, 0)
	entity.target_position = entity.position
	map.combat_module.update_actor_position(player.entity_id, entity.position)
	hall.local_player_controller.set_position(entity.position)
	_reset_observations()
	var before := player.inventory.count_definition(source.item_definition_id)
	var arm := player.vehicle.loadout.at(1)
	var durability_before := arm.durability
	network.request_use_ability("mining.collect", source.position)
	await process_frame
	await process_frame
	server.advance_simulation(3.0)
	await process_frame
	_check(player.inventory.count_definition(source.item_definition_id) == before + 1 and source.remaining == 49, "采矿入包和扣矿同时完成")
	_check(arm.durability == durability_before and arm.usage.progress.get("mining", 0) == 1, "第一次成功采矿立即写回余量但不扣耐久")
	_consistent("采矿")
	var owned := -1
	for task: Dictionary in panels.snapshot_bundle().mission_journal:
		if task.task_id != quest_id: continue
		for requirement: Dictionary in task.requirements:
			if requirement.display_name == "铁矿": owned = requirement.owned
	_check(owned == before + 1, "采矿增量即时更新铁矿任务的实际数量")
	server.advance_simulation(3.0)
	await process_frame
	_check(player.inventory.count_definition(source.item_definition_id) == before + 2 and source.remaining == 48, "第二次成功采矿正常入账")
	_check(arm.durability == durability_before - 1 and arm.usage.progress.get("mining", -1) == 0, "第二次成功采矿立即扣一点耐久并清零余量")
	_check(panels.current_player.vehicle.loadout.at(1).durability == arm.durability, "客户端采掘臂耐久与服务端一致")
	await _check_mining_arm_tooltip("采矿后战车面板提示显示实时耐久")
	var durability_change_sent := false
	for message: Dictionary in messages:
		var vehicle_change: Dictionary = message.get("result", {}).get("value", {}).get("player_change", {}).get("vehicle", {})
		for item: Dictionary in vehicle_change.get("equipped", []):
			if item.get("instance_id") == "collector" and int(item.get("durability", -1)) == durability_before - 1: durability_change_sent = true
	_check(durability_change_sent, "耐久下降通过战车增量传输")
	_consistent("采矿耐久下降")
	server.advance_simulation(3.0)
	await process_frame
	_check(arm.durability == durability_before - 1 and arm.usage.progress.get("mining", 0) == 1, "第三次成功采矿留下可持久化余量")
	var capacity := player.inventory.capacity
	player.inventory.capacity = player.inventory.items().size()
	# 填满已有铁矿堆叠，使新增周期必须创建物品，从而触发容量拒绝。
	for item: GameItem in player.inventory.items():
		if item.definition_id == source.item_definition_id: item.quantity = item.max_stack
	var remaining := source.remaining
	server.advance_simulation(3.0)
	_check(source.remaining == remaining, "满包拒绝不扣矿源")
	_check(arm.durability == durability_before - 1 and arm.usage.progress.get("mining", 0) == 1, "满包拒绝不消耗耐久或累计使用量")
	player.inventory.capacity = capacity
	_check(full_updates == 0 and equipment_updates == 0, "采矿不发送全量或外观刷新")
	await _sync()


func _restart_mining() -> void:
	var store_path := config.player_state_store_path
	var durability := player.vehicle.loadout.at(1).durability
	var usage := player.vehicle.loadout.at(1).usage.to_dictionary()
	await _close()
	if not await _boot("res://data/maps/glory_nft_bl_d04.json", store_path): return
	var arm := player.vehicle.loadout.at(1)
	_check(arm.durability == durability and arm.usage.to_dictionary() == usage, "重启真实主场景和服务器后耐久及使用余量保留")
	_check(panels.current_player.vehicle.loadout.at(1).durability == durability, "重启后的客户端面板恢复相同耐久")
	await _check_mining_arm_tooltip("重启后战车面板提示显示已保存耐久")
	var source: MineSource = server.map_instance.mining_module.sources.values()[0]
	var entity: AuthoritativeEntity = server.map_instance.entities[player.entity_id]
	entity.position = source.position + Vector2(40, 0)
	entity.target_position = entity.position
	server.map_instance.combat_module.update_actor_position(player.entity_id, entity.position)
	hall.local_player_controller.set_position(entity.position)
	network.request_use_ability("mining.collect", source.position)
	await process_frame
	await process_frame
	server.advance_simulation(3.0)
	await process_frame
	_check(arm.durability == durability - 1 and arm.usage.progress.get("mining", -1) == 0, "重启后第一次成功采矿接续旧余量扣一点耐久")
	_check(panels.current_player.vehicle.loadout.at(1).durability == arm.durability, "重启后采矿耐久增量继续同步")
	await _check_mining_arm_tooltip("重启后继续采矿的面板提示保持同步")
	_consistent("重启后采矿")
	server.map_instance.mining_module.interrupt(player.entity_id, &"test")


func _check_mining_arm_tooltip(label: String) -> void:
	var arm := player.vehicle.loadout.at(1)
	var found := false
	for visual: Control in windows.vehicle_panel._slot_root.get_children():
		if visual.is_queued_for_deletion(): continue
		visual.mouse_entered.emit()
		await create_timer(0.11).timeout
		var tooltip := ItemHoverHighlight.active_tooltip() as LegacyItemTooltip
		if tooltip != null and tooltip._title_label.text.contains(arm.display_name):
			found = true
			_check(tooltip._body_label.text.contains("耐久：%d / %d" % [arm.durability, arm.max_durability]), label)
		visual.mouse_exited.emit()
		if tooltip != null: tooltip.hide()
		if found: break
	_check(found, label + "：采掘臂展示节点存在")


## 重复、旧会话和断档恢复必须保护现有对象及最终数量。
func _versions() -> void:
	_reset_observations()
	var older := panels.snapshot_bundle()
	await _send({"type": "move_inventory_item", "instance_id": "ore", "position_px": [40, 40]})
	var payload: Dictionary = messages.back().result.value.player_change.duplicate(true)
	var revision := panels.current_player.revision
	panels.apply_bundle(older)
	_check(panels.current_player.revision == revision and panels.current_player.inventory.find("ore").position_px == Vector2i(40, 40), "旧完整快照不覆盖新背包")
	panels.apply_change(payload)
	_check(panels.current_player.revision == revision, "重复增量幂等")
	payload.sync_id = "old-session"
	payload.transaction_revision = revision + 1
	panels.apply_change(payload)
	_check(panels.current_player.revision == revision, "旧会话增量丢弃")
	payload.sync_id = panels._sync_id
	payload.base_revision = revision + 1
	payload.transaction_revision = revision + 2
	panels.apply_change(payload)
	await process_frame
	await process_frame
	_check(full_updates == 1 and not panels._resync_pending, "版本断档只查询一次并恢复")
	_consistent("断档恢复")
	var quantity := panels.current_player.inventory.find("ore").quantity
	var first := panels.current_player.inventory.find("ore").to_view_dictionary()
	first.amount = quantity - 1
	var invalid := first.duplicate(true)
	invalid.instance_id = "unknown"
	invalid.definition_id = "missing.definition"
	panels.apply_change({"sync_id": panels._sync_id, "base_revision": player.revision,
		"transaction_revision": player.revision + 1, "inventory_revision": player.inventory.revision + 1,
		"items": [first, invalid]})
	_check(panels.current_player.inventory.find("ore").quantity == quantity, "后项校验失败不提前应用前项")
	await process_frame
	await process_frame
	_check(not panels._resync_pending, "非法增量恢复完整同步")


## 真实生产窗口依赖推送；打开、完成、关闭和隐藏生产均保持背包一致。
func _manufacturing() -> void:
	var recipe: ManufacturingRecipe
	for entry: ManufacturingRecipe in server.manufacturing_service._recipe_book.recipes_for_station("refining"):
		if server.player_panel_service.catalog.display_name(entry.product_definition_id) == "铁": recipe = entry
	_check(recipe != null, "真实铁矿提炼配方")
	if recipe == null: return
	player.skills = SkillBook.new({"refining": 100})
	_grant(recipe.materials[0].definition_id, "production.ore", 90)
	await _sync()
	_reset_observations()
	windows.open_manufacturing("refining")
	await process_frame
	await process_frame
	var panel: ManufacturingWindow = windows.manufacturing_window
	for index in panel.recipe_list.item_count:
		if panel._snapshot.recipes[index].id == recipe.recipe_id: panel._select_recipe(index)
	panel.cycles.get_line_edit().text = "3"
	panel.start_button.pressed.emit()
	await process_frame
	await process_frame
	_check(player.production.order != null, "生产按钮启动真实订单")
	if player.production.order == null: return
	var count := commands.size()
	panel._process(3.1)
	_check(commands.size() == count, "制造窗口不再三秒轮询")
	var before := player.inventory.count_definition(recipe.materials[0].definition_id)
	server.advance_simulation(2.1)
	await process_frame
	_check(player.production.order.completed == 1 and panel._snapshot.production.order.completed == 1, "生产完成即时推送")
	_check(player.inventory.count_definition(recipe.materials[0].definition_id) == before - int(recipe.materials[0].quantity), "生产扣料准确")
	_consistent("生产入账")
	panel.pause_button.pressed.emit()
	await process_frame
	await process_frame
	server.advance_simulation(2.1)
	_check(player.production.order.paused and player.production.order.completed == 1, "暂停期间不继续扣料")
	panel.pause_button.pressed.emit()
	await process_frame
	await process_frame
	_check(not player.production.order.paused, "继续生产收到增量状态")
	panel.hide()
	await process_frame
	await process_frame
	_check(server.sessions.session_for_entity(player.entity_id).manufacturing_station.is_empty(), "隐藏窗口取消订阅")
	server.advance_simulation(2.1)
	await process_frame
	_consistent("隐藏期间生产")
	_check(full_updates == 0 and equipment_updates == 0, "生产不全量刷新人物或外观")
	windows.open_manufacturing("refining")
	await process_frame
	await process_frame
	_check(panel._snapshot.production.order.completed == 2, "重开读取最新生产进度")
	var quantity := player.inventory.count_definition(recipe.product_definition_id)
	panel.cancel_button.pressed.emit()
	panel.confirmation.confirmed.emit()
	await process_frame
	await process_frame
	_check(player.production.order == null and panel._snapshot.production.order == null, "取消订单立即同步")
	_check(player.inventory.count_definition(recipe.product_definition_id) == quantity, "取消保留已完成产物")


## 验证正常退出必须等实际保存成功，随后新进程仓储可读最终物品。
func _exit_and_reload() -> void:
	_grant("iron_ore", "exit.ore")
	await _sync()
	var expected := player.inventory.count_definition("iron_ore")
	var exited := [false]
	hall.exit_controller._quit = func() -> void: exited[0] = true
	var repository := server.autosave_service._repository
	server.autosave_service._repository = RejectingSave.new()
	hall.exit_controller.request_exit()
	await process_frame
	await process_frame
	_check(not exited[0] and server.autosave_service.player_for(player.entity_id) != null, "保存失败不退出或释放在线角色")
	server.autosave_service._repository = repository
	hall.exit_controller.request_exit()
	await process_frame
	await process_frame
	_check(exited[0] and server.autosave_service.player_for(player.entity_id) == null, "保存成功后才退出和释放")
	var disk := FilePlayerStateRepository.new(config.player_state_store_path)
	_check(disk.initialize().is_ok and disk.load_player(player.entity_id).is_ok, "正常退出存档可重新读取")
	var restored: Player = PlayerStateMapper.new(server.player_panel_service.catalog).to_domain(disk.load_player(player.entity_id).value).value
	_check(restored.inventory.count_definition("iron_ore") == expected, "退出保存包含最后检查点之后的新增物品")


## 等待真实磁盘落盘并从新仓储读取，防止只验证内存状态。
func _save_and_compare() -> void:
	var notifications := full_updates + equipment_updates
	_check(server.autosave_service.save_all(server._capture_player_runtime).is_ok, "捕获并保存在线状态")
	_check(server.player_state_repository.flush().is_ok, "等待磁盘完成")
	_check(full_updates + equipment_updates == notifications, "保存不触发玩家或装备刷新")
	var repository := FilePlayerStateRepository.new(config.player_state_store_path)
	_check(repository.initialize().is_ok, "重新打开隔离存档")
	var loaded := repository.load_player(player.entity_id)
	_check(loaded.is_ok, "从磁盘重载角色")
	if loaded.is_ok:
		var restored: Player = PlayerStateMapper.new(server.player_panel_service.catalog).to_domain(loaded.value).value
		_check(restored.inventory.layout_items() == player.inventory.layout_items(), "保存重载布局一致")
		_check(restored.vehicle.loadout.at(1).durability == player.vehicle.loadout.at(1).durability, "保存重载主装置耐久一致")
		_check(restored.vehicle.loadout.at(1).usage.to_dictionary() == player.vehicle.loadout.at(1).usage.to_dictionary(), "保存重载主装置使用余量一致")
		for item: GameItem in player.inventory.items():
			_check(restored.inventory.find(item.instance_id).quantity == item.quantity, "保存重载数量 " + item.instance_id)


## 隔离场景释放后才能进入下一组，服务器收尾保持正常保存行为。
func _close() -> void:
	network.disconnect_from_server()
	hall.queue_free()
	await process_frame
	await process_frame


## 每组只统计操作引起的通知，不混入显式准备快照。
func _reset_observations() -> void:
	messages.clear()
	commands.clear()
	full_updates = 0
	equipment_updates = 0


## 汇总失败并保留清晰的逐项定位。
## [param condition] 验证结果。[param message] 被验证行为。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAILED: " + message)
