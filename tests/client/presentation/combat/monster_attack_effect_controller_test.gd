extends SceneTree

const ControllerScript := preload(
	"res://scripts/client/presentation/combat/monster_attack_effect_controller.gd"
)
const MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"

var assertions := 0
var failures: Array[String] = []


## 延迟执行需要节点树生命周期的怪物攻击表现测试。
func _init() -> void:
	call_deferred("_run")


## 验证远程弹体轨迹、事件去重和贴身攻击分支。
func _run() -> void:
	var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_expect(manifest_value is Dictionary, "combat manifest should parse")
	if not manifest_value is Dictionary:
		_finish()
		return
	var world := Node2D.new()
	root.add_child(world)
	var controller = ControllerScript.new()
	root.add_child(controller)
	_expect(controller.configure(manifest_value, world) == OK, "attack controller should configure")
	var ranged := {
		"attack_id": "monster.om.attack.1",
		"attack_archetype": "ranged_projectile",
		"combat_actor_id": "om_adult_standard",
		"origin": [0.0, 0.0],
		"target_position": [100.0, 0.0],
		"projectile_speed": 100.0,
	}
	_expect(controller.present_attack(ranged), "ranged attack should create its mapped projectile")
	_expect(not controller.present_attack(ranged), "replayed attack id should not duplicate a projectile")
	_expect(controller.active_projectile_count() == 1, "one projectile should be active")
	controller.advance(0.5)
	var projectile := world.get_node_or_null("MonsterProjectile_monster_om_attack_1") as Node2D
	_expect(projectile != null and projectile.position.is_equal_approx(Vector2(50.0, 0.0)), "projectile should interpolate by authoritative speed")
	controller.advance(0.5)
	_expect(controller.active_projectile_count() == 0, "projectile should end at its target time")
	var diagonal := ranged.duplicate(true)
	diagonal["attack_id"] = "monster.om.attack.diagonal"
	diagonal["target_position"] = [100.0, 100.0]
	_expect(controller.present_attack(diagonal), "diagonal attack should create its mapped projectile")
	var diagonal_projectile := world.get_node_or_null(
		"MonsterProjectile_monster_om_attack_diagonal"
	) as Node2D
	_expect(
		diagonal_projectile != null
		and is_equal_approx(diagonal_projectile.rotation, PI / 4.0),
		"projectile should rotate its east-facing source frame onto the flight vector",
	)
	controller.advance(2.0)
	var contact := ranged.duplicate(true)
	contact["attack_id"] = "monster.orb.attack.2"
	contact["attack_archetype"] = "contact_melee"
	contact["combat_actor_id"] = "photosensitive_orb_standard"
	_expect(not controller.present_attack(contact), "contact monster should use body attack without a projectile")
	_expect(controller.active_projectile_count() == 0, "contact attack should leave no projectile")
	controller.queue_free()
	world.queue_free()
	_finish()


## 记录布尔断言结果。
## [param condition] 期望条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出测试汇总并设置进程退出码。
func _finish() -> void:
	if failures.is_empty():
		print("MONSTER_ATTACK_EFFECTS_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MONSTER_ATTACK_EFFECTS_FAILED (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
