extends SceneTree

var checks := 0
var failures := PackedStringArray()


## 延迟启动需要真实场景树的效果与事件去重测试。
func _initialize() -> void:
	call_deferred("_run")


## 验证原版脉冲帧序、持续状态、贯穿弹不提前消失及切图清理。
func _run() -> void:
	root.size = Vector2i(1000,800)
	var world := Node2D.new()
	root.add_child(world)
	var player := Node2D.new()
	player.position = Vector2(220,440)
	world.add_child(player)
	var monster_controller := MonsterWorldController.new()
	root.add_child(monster_controller)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/equipment_world/combat_visual_manifest.json"))
	_check(monster_controller.configure(world, manifest, player) == OK, "world controller configure")
	var effects := monster_controller._sama_effects
	effects.set_process(false)
	var snapshot := {"local_entity_id":"tester", "monsters":[], "recent_events":[{"event_id":1,"event_type":"sama_activated","kind":"pulse","attacker_id":"tester","origin":[220,440],"direction":[1,0]}],
		"local_sama_effects":[{"kind":"piercing","remaining_seconds":8.0},{"kind":"fission","remaining_seconds":4.0}]}
	monster_controller.apply_snapshot(snapshot)
	_check(effects._pulses.size() == 1 and effects._statuses.size() == 2, "pulse and source status icons")
	monster_controller.apply_snapshot(snapshot)
	_check(effects._pulses.size() == 1, "network replay never duplicates pulse")
	var pulse: Dictionary = effects._pulses[0]
	_check(pulse.sprites.size() == 8 and pulse.sprites[0].visible and not pulse.sprites[4].visible, "four first row; second delayed")
	var first_texture: Texture2D = pulse.sprites[0].texture
	effects.advance(0.12)
	_check(pulse.sprites[0].texture != first_texture and pulse.sprites[0].offset == SamaEffectController._art.pulse_start.offsets[3], "25 fps original frame and anchor")
	effects.advance(0.13)
	_check(pulse.sprites[4].visible and pulse.sprites[4].texture != null, "second wave begins at 250ms")
	player.position += Vector2(20,30)
	effects.advance(0.01)
	_check(effects._statuses.piercing.node.position == player.position + Vector2(-16,-94), "icons follow visible vehicle")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/sama_effects.png")
	effects.advance(0.44)
	_check(effects._pulses.is_empty(), "700ms lifetime")
	monster_controller.apply_snapshot({"monsters":[],"recent_events":[],"local_sama_effects":[]})
	_check(effects._statuses.is_empty(), "authoritative removal clears icons")
	var weapon := WeaponAttackVisualController.new()
	root.add_child(weapon)
	_check(weapon.configure(manifest, world, &"recruit_energy_cannon") == OK, "weapon configure")
	weapon.set_process(false)
	weapon.set_visual_collision_resolver(_collision)
	var shot := {"shot_id":"piercing.1","input_sequence":7,"actor_position":[0,0],"origin":[0,0],"endpoint":[400,0],"piercing":true,
		"weapon_flight":{"weapon_id":"recruit_energy_cannon","range":400,"minimum_range":0,"projectile_speed":100,"cooldown_seconds":1,"muzzle_forward_offset":0,"muzzle_offset":[0,0]}}
	_check(weapon.present_confirmed_shot(shot), "confirmed piercing projectile")
	weapon.advance(0.1)
	_check(weapon.active_projectile_count() == 1 and weapon.active_impact_count() == 0, "local first collision cannot consume piercing projectile")
	var hit := {"event_id":1,"event_type":"energy_cannon_hit","attacker_id":"tester","input_sequence":7,"impact_position":[30,0],"projectile_continues":true}
	weapon.apply_authoritative_snapshot({"local_entity_id":"tester","recent_events":[hit]}, "energy_cannon.primary")
	_check(weapon.active_projectile_count() == 1 and weapon.active_impact_count() == 1, "contact impact while projectile continues")
	weapon.apply_authoritative_snapshot({"local_entity_id":"tester","recent_events":[hit]}, "energy_cannon.primary")
	_check(weapon.active_impact_count() == 1, "contact replay dedup")
	weapon.apply_authoritative_snapshot({"local_entity_id":"tester","recent_events":[{"event_id":2,"event_type":"sama_fission_hit","attacker_id":"tester","shot_id":"piercing.1","impact_position":[30,0]}]}, "energy_cannon.primary")
	_check(weapon.active_projectile_count() == 1, "secondary fission event never ends energy projectile")
	weapon.apply_authoritative_snapshot({"local_entity_id":"tester","recent_events":[{"event_id":3,"event_type":"energy_cannon_projectile_expired","attacker_id":"tester","input_sequence":7,"impact_position":[400,0]}]}, "energy_cannon.primary")
	_check(weapon.active_projectile_count() == 0, "authoritative final expiry consumes once")
	weapon.free()
	monster_controller.free()
	await process_frame
	world.free()
	print("Sama effects: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 提供始终命中的旧视觉碰撞器以检验贯穿覆盖路径。
## [param from] 起点。[param _to] 终点。
## 返回一次可视碰撞。
func _collision(from: Vector2, _to: Vector2) -> Dictionary:
	return {"hit":true,"position":from}


## 汇总实际效果生命周期断言。
## [param condition] 结果。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
