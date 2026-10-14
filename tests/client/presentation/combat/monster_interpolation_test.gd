extends SceneTree

const MonsterWorldControllerScript := preload(
	"res://scripts/client/presentation/combat/monster_world_controller.gd"
)
const MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"

var assertions := 0
var failures: Array[String] = []


## 等待世界节点入树后开始插值回归。
func _init() -> void:
	call_deferred("_run")


## 验证连续快照平滑移动，以及同帧死亡立即隐藏。
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
	controller.apply_snapshot(_snapshot(10, 1.0, Vector2.ZERO, true, 60))
	controller.apply_snapshot(_snapshot(11, 1.1, Vector2(100.0, 0.0), true, 60))
	var view = world.get_node_or_null("Monster_monster_interpolated")
	_expect(view != null and view.position == Vector2.ZERO, "snapshot application should not jump the existing view")
	controller._position_interpolator.playback_server_time = 1.05
	controller._position_interpolator.advance(0.0)
	_expect(view != null and view.position.is_equal_approx(Vector2(50.0, 0.0)), "rendered position should interpolate between snapshots")
	controller.apply_snapshot(_snapshot(11, 1.1, Vector2(200.0, 0.0), false, 0))
	_expect(view != null and not view.visible, "duplicate tick must still apply authoritative alive state")
	_expect(view != null and view.position.is_equal_approx(Vector2(50.0, 0.0)), "duplicate tick must not overwrite interpolated position")
	controller.clear()
	controller.queue_free()
	world.queue_free()
	_finish()


## 构造带服务器时钟的单怪物快照。
## [param server_tick] 权威帧。
## [param server_time] 权威秒数。
## [param point] 脚点坐标。
## [param alive] 是否存活。
## [param health] 当前生命。
## 返回独立快照。
func _snapshot(server_tick: int, server_time: float, point: Vector2, alive: bool, health: int) -> Dictionary:
	return {
		"server_tick": server_tick,
		"server_time_seconds": server_time,
		"local_entity_id": "player.local",
		"monsters": [{
			"entity_id": "monster.interpolated",
			"species_id": "om_adult",
			"display_name": "奥姆虫",
			"combat_actor_id": "om_adult_standard",
			"position": [point.x, point.y],
			"health": health,
			"max_health": 60,
			"alive": alive,
			"action": "idle",
			"facing_index": 0,
		}],
		"recent_events": [],
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
		print("MONSTER_INTERPOLATION_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
