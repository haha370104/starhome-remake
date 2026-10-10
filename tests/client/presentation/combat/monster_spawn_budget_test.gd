extends SceneTree

const MonsterWorldControllerScript := preload(
	"res://scripts/client/presentation/combat/monster_world_controller.gd"
)
const MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"
const MONSTER_COUNT := 25

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_expect(manifest_value is Dictionary, "combat manifest should parse")
	if not manifest_value is Dictionary:
		_finish()
		return
	var world := Node2D.new()
	root.add_child(world)
	var local_player := Node2D.new()
	world.add_child(local_player)
	var controller = MonsterWorldControllerScript.new()
	root.add_child(controller)
	_expect(controller.configure(world, manifest_value, local_player) == OK, "monster controller should configure")
	controller.apply_snapshot(_snapshot())
	_expect(controller._views.size() == 10, "initial monster creation must respect the ten-view frame budget")
	_expect(controller._pending_monsters.size() == 15, "remaining monsters must stay pending after the first budget slice")
	await process_frame
	await process_frame
	_expect(controller._views.size() == 20, "the next frame must materialize exactly one more budget slice")
	await process_frame
	_expect(controller._views.size() == MONSTER_COUNT, "pending monsters must drain without changing authoritative count")
	var previous_ids: Dictionary = {}
	for view: MonsterWorldView in controller._views.values():
		previous_ids[view.get_instance_id()] = true
	controller.apply_snapshot({"server_tick": 2, "monsters": [], "recent_events": []})
	_expect(controller._views.is_empty(), "an empty snapshot must release all active views")
	_expect(controller._view_pool.size() == MONSTER_COUNT, "released monster views must enter the pool")
	controller.apply_snapshot({"server_tick": 3, "monsters": [_monster("monster.reused")], "recent_events": []})
	var reused_view: MonsterWorldView = controller._views.get("monster.reused")
	_expect(reused_view != null and previous_ids.has(reused_view.get_instance_id()), "the next monster must reuse a released view")
	controller.clear()
	controller.queue_free()
	world.queue_free()
	_finish()


func _snapshot() -> Dictionary:
	var monsters: Array[Dictionary] = []
	for index in range(MONSTER_COUNT):
		monsters.append(_monster("monster.%02d" % index))
	return {"server_tick": 1, "monsters": monsters, "recent_events": []}


func _monster(entity_id: String) -> Dictionary:
	return {
		"entity_id": entity_id,
		"species_id": "om_adult",
		"display_name": "奥姆虫",
		"combat_actor_id": "om_adult_standard",
		"position": [float(entity_id.trim_prefix("monster.").to_int() * 32), 220.0],
		"health": 60,
		"max_health": 60,
		"alive": true,
		"action": "idle",
		"facing_index": 0,
	}


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("MONSTER_SPAWN_BUDGET_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
