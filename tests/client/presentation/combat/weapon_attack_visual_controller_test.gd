extends SceneTree

const ControllerScript := preload(
	"res://scripts/client/presentation/combat/weapon_attack_visual_controller.gd"
)
const MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"
const WEAPON_ID := &"recruit_energy_cannon"

var failures: Array[String] = []
var assertions := 0


## 运行新兵能量炮的射程钳制、冷却及弹体到命中特效生命周期测试。
func _initialize() -> void:
	var world_parent := Node2D.new()
	root.add_child(world_parent)
	var controller: Node = ControllerScript.new()
	root.add_child(controller)
	var manifest_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(MANIFEST_PATH)
	)
	_expect(manifest_value is Dictionary, "combat visual manifest should parse")
	if manifest_value is Dictionary:
		_expect(
			controller.configure(manifest_value, world_parent, WEAPON_ID) == OK,
			"starter cannon effects should configure",
		)
		_test_fire_lifecycle(controller)
	controller.free()
	world_parent.free()
	_finish()


## 验证 [param controller] 会钳制远距离点击、抑制冷却重复射击并清理完成特效。
func _test_fire_lifecycle(controller: Node) -> void:
	var first: Dictionary = controller.request_fire(Vector2(100, 100), Vector2(600, 100))
	_expect(bool(first.get("ok", false)), "first field shot should start")
	_expect(bool(first.get("range_clamped", false)), "shot beyond 250 pixels should clamp")
	_expect(
		Vector2(first.get("resolved_target", Vector2.ZERO)).is_equal_approx(Vector2(350, 100)),
		"clamped shot should end at the configured visual range",
	)
	_expect(controller.active_projectile_count() == 1, "shot should create one projectile")
	var cooling: Dictionary = controller.request_fire(Vector2.ZERO, Vector2(100, 0))
	_expect(
		not bool(cooling.get("ok", false)) and cooling.get("code") == &"cooldown",
		"second immediate shot should be visually cooling down",
	)
	controller.advance(0.5)
	_expect(controller.active_projectile_count() == 0, "projectile should reach its target")
	_expect(controller.active_impact_count() == 1, "arrival should create one impact effect")
	controller.advance(0.1)
	_expect(controller.active_impact_count() == 0, "eight-frame impact should finish once")
	controller.advance(0.2)
	_expect(is_zero_approx(controller.cooldown_remaining()), "visual cooldown should expire")
	var too_close: Dictionary = controller.request_fire(Vector2.ZERO, Vector2.ONE)
	_expect(
		not bool(too_close.get("ok", false)) and too_close.get("code") == &"target_too_close",
		"near-zero aim should not create an invalid projectile",
	)
	controller.set_visual_collision_resolver(_fake_visual_collision)
	var collision_shot: Dictionary = controller.request_fire(Vector2.ZERO, Vector2(200, 0))
	_expect(bool(collision_shot.get("ok", false)), "visual-collision shot should start")
	controller.advance(0.2)
	_expect(controller.active_projectile_count() == 0, "continuous segment collision should stop projectile early")
	_expect(controller.active_impact_count() == 1, "visual monster collision should spawn impact immediately")
	controller.clear_effects()
	_expect(
		controller.active_projectile_count() == 0 and controller.active_impact_count() == 0,
		"map cleanup should leave no transient effects",
	)


## 返回测试线段与 X=80 交叉时的纯表现碰撞，不模拟任何权威伤害。
## [param segment_start] 测试弹体在本帧开始时的位置。
## [param segment_end] 测试弹体在本帧结束时的位置。
## Returns 线段跨过测试平面时返回命中点，否则返回 `hit=false`。
func _fake_visual_collision(segment_start: Vector2, segment_end: Vector2) -> Dictionary:
	if segment_start.x <= 80.0 and segment_end.x >= 80.0:
		return {"hit": true, "position": Vector2(80, 0)}
	return {"hit": false}


## 记录 [param condition] 断言，并用 [param message] 保存失败上下文。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出测试汇总，并依据累计失败数量设置进程退出码。
func _finish() -> void:
	if failures.is_empty():
		print("WEAPON ATTACK VISUAL TESTS PASSED: %d assertions" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"WEAPON ATTACK VISUAL TESTS FAILED: %d assertions, %d failures"
		% [assertions, failures.size()]
	)
	quit(1)
