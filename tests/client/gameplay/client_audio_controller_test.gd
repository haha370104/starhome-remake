extends SceneTree

var failures: Array[String] = []


## 验证已物化原版音频能按地图和权威事件进入实际播放器。
func _initialize() -> void:
	call_deferred("_run")


## 执行音频目录、曲目和事件去重的最小集成检查。
func _run() -> void:
	for bus: String in ["Music", "Effects"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	var listener := Node2D.new()
	root.add_child(listener)
	var audio := ClientAudioController.new()
	root.add_child(audio)
	_check(audio.configure(listener), "Glory audio catalog loads")
	var hall := MapDefinition.new()
	hall.legacy_codes = PackedStringArray(["RoomSvr1"])
	audio.set_map(hall)
	_check(audio._current_track == "city.mp3" and audio._music.playing,
		"hall starts its original city music")
	_check(audio._music.stream.get_length() > 0.0, "music bytes decode to a playable stream")
	var historical := {"event_id": 1, "event_type": "energy_cannon_projectile_spawned",
		"actor_position": [0, 0]}
	audio.on_combat_snapshot({"local_mining": {"active": false}, "recent_events": [historical]})
	_check(not _has_effect(audio), "first snapshot does not replay historical fire")
	audio.on_combat_event(historical)
	_check(not _has_effect(audio), "reliable duplicate stays silent")
	audio.on_combat_event({"event_id": 2, "event_type": "energy_cannon_projectile_spawned",
		"actor_position": [0, 0]})
	_check(_has_effect(audio), "new confirmed shot plays an effect")
	for effect_player: AudioStreamPlayer in audio._effects:
		effect_player.stop()
	var player := Player.new()
	audio.on_player_changed(player)
	_check(not _has_effect(audio), "initial equipment snapshot stays silent")
	var shirt := Clothing.new({"id": "shirt", "character_slot": "upper_body"},
		{"instance_id": "shirt-1"})
	player.character_equipment.restore(shirt)
	audio.on_player_changed(player)
	_check(audio._effects[0].playing and audio._effects[0].stream == audio._effect_stream("equipment_equip"),
		"confirmed equipment install plays its original cue")
	for effect_player: AudioStreamPlayer in audio._effects:
		effect_player.stop()
	audio.on_player_changed(player)
	_check(not _has_effect(audio), "unchanged equipment stays silent")
	player.character_equipment.unequip("upper_body")
	audio.on_player_changed(player)
	_check(audio._effects[0].playing and audio._effects[0].stream == audio._effect_stream("equipment_unequip"),
		"confirmed equipment removal plays its original cue")
	for effect_player: AudioStreamPlayer in audio._effects:
		effect_player.stop()
	audio.on_combat_event({"event_id": 3, "event_type": "energy_cannon_hit", "damage": 10,
		"impact_position": [0, 0], "death": {"event_type": "monster_died", "position": [0, 0]}})
	_check(audio._effects[0].playing and audio._effects[0].stream == audio._effect_stream("monster_death"),
		"fatal hit plays monster explosion instead of impact")
	audio.set_moving(true)
	_check(audio._movement.playing, "movement loop starts")
	audio.set_moving(false)
	_check(not audio._movement.playing, "movement loop stops")
	var field := MapDefinition.new()
	field.legacy_codes = PackedStringArray(["D04"])
	audio.set_map(field)
	_check(audio._current_track == "basemic.mp3" and audio._music.playing,
		"field switches to its original music")
	var unlisted_field := MapDefinition.new()
	unlisted_field.category = "field"
	unlisted_field.legacy_codes = PackedStringArray(["B02"])
	audio.set_map(unlisted_field)
	_check(audio._current_track == "basemic.mp3", "unlisted field uses documented remake fallback")
	audio._music.stop()
	for effect_player: AudioStreamPlayer in audio._effects:
		effect_player.stop()
	await create_timer(1.0).timeout
	if failures.is_empty():
		print("CLIENT_AUDIO_CONTROLLER_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 检查音效池是否已有实际播放节点。
## [param audio] 待检查的音频控制器。
## 返回是否有正在播放的音效。
func _has_effect(audio: ClientAudioController) -> bool:
	for player: AudioStreamPlayer in audio._effects:
		if player.playing:
			return true
	return false


## 累计失败的音频行为断言。
## [param passed] 实际结果。[param message] 失败说明。
func _check(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)
