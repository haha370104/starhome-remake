extends SceneTree

const MonsterWorldControllerScript := preload(
	"res://scripts/client/presentation/combat/monster_world_controller.gd"
)
const MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"
const MONSTER_COUNT := 25

var assertions := 0
var failures: Array[String] = []


## 等待世界节点入树后开始插值回归。
func _init() -> void:
	call_deferred("_run")


## 验证单帧创建上限、重复快照不超预算与清理未创建实体。
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
	controller.apply_snapshot(_snapshot())
	_expect(controller._views.size() == 10, "multiple snapshots in one frame cannot reset the budget")
	var previous_count := 10
	for frame in range(6):
		await process_frame
		var current_count: int = controller._views.size()
		_expect(current_count - previous_count <= 10, "one render frame must never create more than ten views")
		previous_count = current_count
	_expect(previous_count == MONSTER_COUNT, "pending monsters must drain without changing authoritative count")
	controller.apply_snapshot({"server_tick": 2, "monsters": [], "recent_events": []})
	_expect(controller._views.is_empty() and controller._pending_monsters.is_empty(), "empty snapshot removes views and pending work")
	controller.clear()
	controller.queue_free()
	world.queue_free()
	_finish()


## 构造批量出生快照。
## 返回包含固定数量怪物的快照。
func _snapshot() -> Dictionary:
	var monsters: Array[Dictionary] = []
	for index in range(MONSTER_COUNT):
		monsters.append(_monster("monster.%02d" % index))
	return {"server_tick": 1, "monsters": monsters, "recent_events": []}


## 构造具有原有素材映射的怪物。
## [param entity_id] 唯一怪物编号。
## 返回怪物快照。
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


## 记录回归断言。
## [param condition] 预期为真的条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出结果并结束测试进程。
func _finish() -> void:
	if failures.is_empty():
		print("MONSTER_SPAWN_BUDGET_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
