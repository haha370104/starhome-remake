extends SceneTree

var checks := 0
var failures: Array[String] = []
var _state: PlayerStateRecord
var _service: AuthoritativeCommerceService
var _window: WeaponMerchantWindow


## 创建实际训练任务窗口，检查交互、日志与发布者投放。
func _initialize() -> void:
	call_deferred("_run")


## 实际服务驱动五任务选择、接取、进度和任务日志，并检查新增NPC导航落点。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	_expect(RuntimeContentBootstrap.mount_default().get("ok", false), "内容包挂载")
	var fixture := PlayerPanelServiceFixture.new()
	_expect(fixture.initialize().is_ok, "玩家夹具")
	_state = fixture._state.duplicate_record()
	_state.map_id = "yian_harbor_hall_floor_1"
	_service = AuthoritativeCommerceService.new()
	_expect(_service.initialize().is_ok, "服务初始化")
	_window = WeaponMerchantWindow.new()
	root.add_child(_window)
	_window.command_requested.connect(_dispatch)
	_window.open_mode("task", "combat_trainer")
	await process_frame
	_expect(_window._task_selector.visible and _window._task_selector.item_count == 5, "五种训练可选择")
	_expect(_window._task_selector.position.y + _window._task_selector.size.y <= _window._task_message.position.y, "选项不覆盖正文")
	_window._select_task(4)
	_expect(_window._selected_task_id == "training_repair", "可选维修训练")
	_window._request_task_action()
	await process_frame
	_expect(_state.quest_states.get("training_repair", {}).get("accepted", false), "领取选中的维修任务而非默认能量炮")
	_expect(_window._task_primary_button.disabled, "未完成禁止交付")
	_window._select_task(0)
	_window._request_task_action()
	await process_frame
	_expect(_state.quest_states.size() == 2, "两种训练可以并行")
	var target := String(_state.quest_states["training_energy_cannon"]["target"]["species_id"])
	for index in range(20):
		var killed := _service.record_monster_kill(_state, {"killer_id": _state.character_id, "species_id": target, "death_id": "ui.%d" % index})
		_expect(killed.is_ok, "击杀服务结算")
		if killed.value.get("changed", false):
			_state = killed.value["candidate"]
	_dispatch({"type": "query_weapon_merchant", "merchant_id": "combat_trainer"})
	await process_frame
	_expect(not _window._task_primary_button.disabled, "目标完成可领奖")
	_window._request_task_action()
	await process_frame
	_expect("等级提升1级" in _window._task_message.text, "完成消息显示技能奖励")
	var journal := MissionJournalPanel.new()
	root.add_child(journal)
	var bundle := _service.build_bundle(_state, {"merchant_id": "combat_trainer"})
	journal.apply_entries(bundle["mission_journal"])
	_expect(journal.listing.item_count == 2, "日志包含两种已接或完成训练")
	journal._show_detail(0)
	_expect("今日接取" in journal.details.text and "等级 +1" in journal.details.text, "日志显示每日额度和技能奖励")
	_expect("武器商人" not in journal.details.text, "训练日志不误导到武器商人")
	_window.open_mode("task", "ore_merchant")
	await process_frame
	_expect(not _window._task_selector.visible, "单个材料任务不显示训练选择器")
	_expect("铁矿" in _window._task_message.text or _window._task_progress.get_child_count() > 0, "矿物任务可打开")
	_check_npcs()
	journal.free()
	_window.free()
	for failure in failures:
		push_error(failure)
	print("TRAINING_TASKS_RUNTIME: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 将窗口意图交给真实权威服务并刷新已提交快照。
## [param command] 窗口生成的任务命令。
func _dispatch(command: Dictionary) -> void:
	var result := _service.execute(_state, command)
	_expect(result.is_ok, "窗口命令：" + result.error_message)
	if not result.is_ok:
		return
	if result.value.get("changed", false):
		_state = result.value["candidate"]
	_window.apply_commerce_bundle(result.value["panel_bundle"])


## 核对每个任务发布者的场景路由、导航及可达落点。
func _check_npcs() -> void:
	var npcs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/npcs/yian_harbor_hall_floor_1.json"))
	var directory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/glory_map_directory_v1.json"))
	for provider: String in _service.quests.catalog.providers:
		var map_id := String(_service.quests.catalog.providers[provider]["map_ids"][0])
		var entries: Array = npcs["npcs"] if map_id == "yian_harbor_hall_floor_1" else npcs["maps"].get(map_id, [])
		var found := false
		for entry: Dictionary in entries:
			if String(entry["id"]) != provider:
				continue
			found = true
			_expect(String(entry.get("interaction_service", "")) == "commerce", "NPC从配置路由到任务消费器")
			var model := NpcBase.new()
			_expect(model.configure(entry).is_ok, "NPC模型合法：" + provider)
			var loader := MapDefinitionLoader.new()
			var map := loader.load_file(String(directory["definitions"][map_id]))
			_expect(map != null, "任务所在地图可加载")
			if map == null:
				continue
			var navigation := DiamondNavigation.new()
			_expect(navigation.load_from(map.navigation_data_path, map.navigation_grid_size, map.navigation_cell_size), "NPC导航加载")
			var spawn := Vector2(float(entry["spawn"][0]), float(entry["spawn"][1]))
			var resolved := spawn if navigation.is_walkable(spawn) else navigation.closest_walkable_position(spawn)
			_expect(resolved.is_finite() and resolved.distance_to(spawn) <= 48.0, "NPC落点应位于配置位置附近的可走地面：" + provider)
			print("QUEST_NPC %s %s %s" % [provider, map_id, resolved])
		_expect(found, "NPC已经放入对应地图：" + provider)


## 累计窗口与地图检查。
## [param condition] 当前预期条件。
## [param message] 失败诊断。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
