extends SceneTree

var checks := 0
var failures: Array[String] = []


## 延迟构造场景，检验独立日志与正式大厅中的被动订阅。
func _initialize() -> void:
	call_deferred("_run")


## 覆盖持久化、清除后重播、非法文件、写盘失败及真实窗口入口。
func _run() -> void:
	root.size = Vector2i(1100, 760)
	var path := "res://.godot/journal-%d.cfg" % OS.get_process_id()
	var journal := PveDeathJournal.new()
	_check(journal.open(path) == OK and journal.entries().is_empty(), "新角色空日志")
	var event := _event("one")
	_check(not journal.record(event, "someone.else", "地图A"), "只记录本人")
	var nondeath := event.duplicate(true)
	nondeath.target_destroyed = false
	_check(not journal.record(nondeath, "journal.player", "地图A"), "普通受击不记死亡")
	_check(journal.record(event, "journal.player", "地图A"), "记录权威事件")
	_check(not journal.record(event, "journal.player", "地图B"), "重复快照不重复也不改地图")
	_check(journal.save() == OK, "日志写盘")
	var reopened := PveDeathJournal.new()
	_check(reopened.open(path) == OK and reopened.entries() == journal.entries(), "跨重启保留")
	var copy := reopened.entries()
	copy[0].source = "篡改"
	_check(reopened.entries()[0].source == "低温毒胶", "展示不能改内部记录")
	_check(reopened.clear() == OK and reopened.entries().is_empty(), "明确清除持久化")
	_check(not reopened.record(event, "journal.player", "地图A"), "清除后重复快照不复活记录")
	_check(journal.open(path) == OK and not journal.record(event, "journal.player", "地图A"), "重启后也保留已清除身份")
	for index in range(120): journal.record(_event(str(index)), "journal.player", "地图A")
	_check(journal.entries().size() == 100 and journal.entries()[0].id == "119", "限定最近100条且最新在前")
	_check(journal.save() == OK and reopened.open(path) == OK and reopened.entries().size() == 100, "满日志往返")
	var broken := ConfigFile.new()
	broken.set_value("journal", "entries", [journal.entries()[0], {"id": "bad"}])
	broken.save(path)
	_check(reopened.open(path) == ERR_INVALID_DATA and reopened.entries().is_empty(), "非法文件不能部分加载")
	_check(reopened.open("res://.godot/nonexistent-journal-%d/data.cfg" % OS.get_process_id()) == OK, "隔离失败写盘路径")
	reopened.record(event, "journal.player", "地图A")
	_check(reopened.clear() != OK and reopened.entries().size() == 1, "清除写盘失败保留记录")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var hall: Node2D = load("res://scenes/main_hall.tscn").instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	var controller: PveDeathJournalController = hall.interactions.death_journal
	var session: PlayerPanelSession = hall.panel_session
	var fixture := PlayerPanelServiceFixture.new()
	_check(fixture.initialize().is_ok, "初始化真实面板投影")
	fixture._state.character_id = "journal.player"
	session.apply_bundle(fixture.execute({"type": "query"}).value)
	controller.journal.clear()
	event = _event("scene-%d" % OS.get_process_id())
	hall.multiplayer_presenter.map_joined.emit(hall.active_world_controller.definition.map_id, "map.fixture", Vector2.ZERO, 1)
	hall.multiplayer_presenter.combat_event_received.emit(event)
	hall.multiplayer_presenter.combat_snapshot_received.emit({"recent_events": [event]})
	_check(hall.interactions.smart_assistant == null and controller.journal.entries().size() == 1, "未打开智脑已订阅且快照去重")
	var manager: GameWindowManager = hall.game_window_manager
	var window: PveDeathJournalPanel = manager.navigation_windows.pve_death_journal
	manager.toggle("smart_assistant")
	manager.navigation_windows.smart_assistant.journal_requested.emit()
	_check(window.visible and window.listing.text.contains("低温毒胶") and window.listing.text.contains("毒雾持续伤害"), "智脑入口显示真实来源")
	_check(not window.listing.bbcode_enabled, "来源文字不会解析为标记")
	window._ask_clear()
	_check(window.confirmation.visible and controller.journal.entries().size() == 1, "清除需要确认且尚未删除")
	window.confirmation.hide()
	window._ask_clear()
	window.confirmation.confirmed.emit()
	_check(controller.journal.entries().is_empty() and window.listing.text == "暂无记录", "确认后清除模型和窗口")
	hall.multiplayer_presenter.combat_snapshot_received.emit({"recent_events": [event]})
	_check(controller.journal.entries().is_empty(), "正式订阅清除后重播也不重新添加")
	window.confirmation.hide()
	hall.multiplayer_presenter.combat_event_received.emit(_event("capture-%d" % OS.get_process_id()))
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/pve_death_journal.png")
	hall.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("PVE_DEATH_JOURNAL_%s (%d checks)" % ["OK" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


## 创建与权威事件相同形状的日志输入，不据此修改任何游戏存档。
## [param identity] 用于检验跨快照身份的唯一值。
## 返回腐蚀击毁事件。
func _event(identity: String) -> Dictionary:
	return {"event_type": "monster_attack_resolved", "target_entity_id": "journal.player",
		"target_destroyed": true, "death_id": identity, "death_time": 1800000000,
		"death_map_instance_id": "map.fixture", "attacker_display_name": "低温毒胶",
		"impact_position": [120, 330], "damage": 10, "corrosion_pulse": true}


## 汇总断言，允许同时查看边界失败。
## [param condition] 预期条件。[param message] 可读原因。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
