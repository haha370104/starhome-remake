extends SceneTree

var checks := 0
var failures := PackedStringArray()


## 延迟启动实际场景节点检查。
func _initialize() -> void:
	call_deferred("_run")


## 验证原版NPC白色致命伤害反馈、事件去重以及穿透弹不会被附加事件提前结束。
func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var player := Node2D.new()
	world.add_child(player)
	var controller := MonsterWorldController.new()
	root.add_child(controller)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/equipment_world/combat_visual_manifest.json"))
	_check(controller.configure(world, manifest, player) == OK, "actual presentation configure")
	var event := {"event_id":1, "event_type":"central_fatal_hit", "attacker_id":"tester", "target_entity_id":"monster",
		"shot_id":"shot.1", "impact_position":[300,300], "damage":50, "target_health":100}
	var snapshot := {"local_entity_id":"tester", "monsters":[], "recent_events":[event]}
	controller.apply_snapshot(snapshot)
	var view := world.get_node_or_null("DamageFloat_1") as CombatDamageFloat
	_check(view != null, "actual damage event creates feedback")
	if view != null:
		var label := view.get_child(0) as Label
		_check(label.text == "致命一击 -50" and label.get_theme_color("font_color") == Color.WHITE, "original white damage semantics")
		_check(view.position == Vector2(300,278), "world contact anchored above ordinary damage")
	controller.apply_snapshot(snapshot)
	var count := 0
	for child: Node in world.get_children():
		if child is CombatDamageFloat: count += 1
	_check(count == 1, "network event replay deduplicated")
	var weapon := WeaponAttackVisualController.new()
	root.add_child(weapon)
	_check(weapon.configure(manifest, world, &"recruit_energy_cannon") == OK, "actual weapon visual")
	weapon.set_process(false)
	var shot := {"shot_id":"shot.1", "input_sequence":7, "actor_position":[0,0], "origin":[0,0], "endpoint":[400,0], "piercing":true,
		"weapon_flight":{"weapon_id":"recruit_energy_cannon", "range":400, "minimum_range":0, "projectile_speed":100, "cooldown_seconds":1, "muzzle_forward_offset":0, "muzzle_offset":[0,0]}}
	_check(weapon.present_confirmed_shot(shot), "confirmed projectile")
	weapon.apply_authoritative_snapshot(snapshot, "energy_cannon.primary")
	_check(weapon.active_projectile_count() == 1, "fatal event does not consume original projectile")
	weapon.free()
	controller.free()
	world.free()
	await process_frame
	print("Central hit presentation: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总实际节点断言。
## [param condition] 条件。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
