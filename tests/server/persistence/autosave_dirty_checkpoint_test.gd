extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = "res://data/maps/glory_nft_bl_d04.json"
	config.map_catalog_path = "res://tests/fixtures/nonexistent_map_catalog.json"
	config.default_spawn = Vector2(2412, 2400)
	config.autosave_interval_seconds = 0.25
	config.player_state_store_path = "user://autosave-dirty/state_%d_%d.json" % [
		OS.get_process_id(), Time.get_ticks_msec(),
	]
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "服务器初始化")
	var opened := server.open_session(121, {
		"protocol_version": config.protocol_version,
		"content_version": config.content_version,
	}, 0)
	_check(opened.ok, "建立测试会话")
	var session := server.sessions.session_for_peer(121)
	var identity := session.entity_id
	var autosave := server.autosave_service
	var captured: Array[Array] = []
	var captured_domains: Array[Array] = []
	var collector := func(state: PlayerStateRecord, domains: Array[String] = []) -> DomainResult:
		captured.append([])
		captured_domains.append(domains.duplicate())
		return DomainResult.ok(state)

	_check(autosave.dirty_domains_for(identity).size() > 0, "新角色初始状态标记 dirty")
	var saved := autosave.save_dirty(collector)
	_check(saved.is_ok and int(saved.value) == 1 and captured.size() == 1, "首次检查点只捕获 dirty 角色")
	_check(autosave.dirty_domains_for(identity).is_empty(), "成功保存后清除 dirty")
	_check(captured_domains[0].has("location") and captured_domains[0].has("inventory"), "初次捕获包含完整领域")
	var clean_save := autosave.save_dirty(collector)
	_check(clean_save.is_ok and captured.size() == 1, "无 dirty 角色不重复捕获")

	var player: Player = autosave.player_for(identity)
	player.skills = SkillBook.new(player.skills.to_dictionary())
	var committed := autosave.apply_skill_progression(identity, func(_progression: PlayerSkillProgression) -> DomainResult:
		return DomainResult.ok({"upgraded": true, "visible_progress_changed": true})
	)
	_check(committed.is_ok, "技能领域提交")
	_check(autosave.dirty_domains_for(identity).has("skills"), "技能提交只标记技能领域")
	saved = autosave.save_dirty(collector)
	_check(saved.is_ok and captured.size() == 2, "技能 dirty 触发一次捕获")
	_check(captured_domains[1] == ["character", "skills"], "技能捕获保持领域边界")
	_check(not captured_domains[1].has("location"), "技能捕获不读取地图位置")

	autosave.mark_dirty(identity, ["inventory"])
	var rejected := autosave.save_dirty(func(_state: PlayerStateRecord, _domains: Array[String] = []) -> DomainResult:
		return DomainResult.failure(&"test.capture_failed", "模拟捕获失败")
	)
	_check(not rejected.is_ok and autosave.dirty_domains_for(identity).has("inventory"), "捕获失败保留 dirty")

	var writer := BackgroundFileWriter.new()
	var writer_path := ProjectSettings.globalize_path(
		"user://autosave-dirty/writer_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_msec()]
	)
	_check(writer.enqueue_snapshot(writer_path, {"version": 1}) == OK, "后台快照入队")
	_check(writer.enqueue_snapshot(writer_path, {"version": 2}) == OK, "新快照覆盖旧队列")
	_check(writer.checkpoint_merge_count == 1, "同路径 checkpoint 合并一次")
	_check(writer.start() == OK and writer.flush().is_ok, "后台快照写盘")
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(writer_path))
	_check(document is Dictionary and int(document.version) == 2, "后台只落盘最新快照")
	writer.close()
	for path: String in [writer_path, writer_path + ".tmp", writer_path + ".bak"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	server.free()
	for failure: String in failures: push_error(failure)
	print("AUTOSAVE_DIRTY_OK (%d assertions)" % checks)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
