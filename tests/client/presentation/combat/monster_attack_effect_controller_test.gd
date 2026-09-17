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
	_expect(
		controller.present_contact_impact(contact, Vector2(25.0, 30.0)),
		"resolved contact attack should create its vehicle overlay",
	)
	_expect(
		not controller.present_contact_impact(contact, Vector2(25.0, 30.0)),
		"replayed contact impact should be deduplicated",
	)
	var impact := world.get_node_or_null(
		"MonsterContactImpact_monster_orb_attack_2"
	) as Node2D
	_expect(
		impact != null and impact.position == Vector2(25.0, 30.0),
		"contact impact should use the authoritative target position",
	)
	_expect(controller.active_contact_impact_count() == 1, "one contact impact should be active")
	controller.advance(0.34)
	_expect(controller.active_contact_impact_count() == 0, "five 66 ms frames should finish after 0.33 seconds")
	await _test_corrosion(controller, world)
	controller.queue_free()
	world.queue_free()
	_finish()


## 验证毒雾使用八方向喷吐原图，残留依快照重建、附着跟随及切图清理。
## [param controller] 实际怪物攻击表现组件。
## [param world] 活动世界节点。
func _test_corrosion(controller: MonsterAttackEffectController, world: Node2D) -> void:
	controller.set_process(false)
	var capture_viewport: SubViewport
	if "--capture" in OS.get_cmdline_user_args():
		capture_viewport = SubViewport.new()
		capture_viewport.size = Vector2i(1000, 600)
		capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(capture_viewport)
		world.reparent(capture_viewport)
	var player := Node2D.new()
	player.position = Vector2(220, 530)
	world.add_child(player)
	for direction in range(8):
		var origin := Vector2(130 + (direction % 4) * 240, 140 + floori(direction / 4.0) * 240)
		var target := origin + Vector2.from_angle(-direction * PI / 4.0) * 110
		var attack := {"attack_id": "gel.%d" % direction, "attack_archetype": "corrosive_projectile",
			"combat_actor_id": "toxic_gel_cold", "origin": [origin.x, origin.y],
			"target_position": [target.x, target.y], "projectile_speed": 110}
		_expect(controller.present_attack(attack), "每个方向可以创建原版喷吐")
		_expect(not controller.present_attack(attack), "腐蚀开始事件重放不重复生成")
		var flight: CorrosiveEffectController.Flight = controller._corrosion._flights["gel.%d" % direction]
		_expect(flight.first_frame == direction * 5, "选择正确的五帧方向组")
		_expect(flight.node.position == origin, "喷吐从嘴部生长，不把整条特效平移")
		if "--capture" in OS.get_cmdline_user_args():
			var label := Label.new()
			label.text = ["东", "东北", "北", "西北", "西", "西南", "南", "东南"][direction]
			label.position = origin + Vector2(-10, 30)
			label.add_theme_font_override("font", preload("res://assets/ui/fonts/legacy_panel_font.tres"))
			world.add_child(label)
	controller.advance(0.81)
	var snapshot := {"local_entity_id": "p", "corrosive_clouds": [
		{"effect_id": "attached", "attached_actor_id": "p", "position": [200, 514]},
		{"effect_id": "ground", "attached_actor_id": "", "position": [650, 530]},
	]}
	controller.apply_corrosion_snapshot(snapshot, player)
	controller.apply_corrosion_snapshot(snapshot, player)
	_expect(controller._corrosion._clouds.size() == 2, "新加入可以从完整快照重建且不重复")
	var attached: CorrosiveEffectController.Cloud = controller._corrosion._clouds.attached
	var ground: CorrosiveEffectController.Cloud = controller._corrosion._clouds.ground
	_expect(attached.node.position == player.position + Vector2(0, -16), "附着使用本地预测位置")
	player.position.x += 40
	controller.advance(0.01)
	_expect(attached.node.position == player.position + Vector2(0, -16), "两次网络快照之间也会跟随战车")
	_expect(ground.node.position == Vector2(650, 530), "地面毒雾不会跟着战车移动")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		capture_viewport.get_texture().get_image().save_png("res://.godot/corrosion-slow-spray.png")
	controller.settle_corrosion_attack({"attack_id": "gel.0"})
	_expect(controller.active_projectile_count() == 7, "实际撞击会结束在途状态")
	var fading: CorrosiveEffectController.Flight = controller._corrosion._flights["gel.0"]
	_expect(fading.settled and fading.node.modulate.a == 1.0, "命中不瞬间删除喷雾，开始独立消散")
	controller.advance(1.61)
	_expect(controller._corrosion._flights.size() == 8 and fading.node.modulate.a > 0.0, "喷吐完成后1.61秒仍在消散")
	if capture_viewport != null:
		await RenderingServer.frame_post_draw
		capture_viewport.get_texture().get_image().save_png("res://.godot/corrosion-slow-fade.png")
	controller.settle_corrosion_attack({"attack_id": "gel.0"})
	controller.advance(1.38)
	_expect(controller._corrosion._flights.has("gel.0") and fading.fade_elapsed > 2.98, "重复结算不重置消散时钟，三秒前仍存在")
	controller.advance(0.02)
	_expect(not controller._corrosion._flights.has("gel.0"), "达到三秒消散期限才释放喷吐")
	_expect(controller._corrosion._clouds.size() == 2, "残留800ms循环多次，不按一次性命中特效删掉")
	controller.apply_corrosion_snapshot({"corrosive_clouds": []}, player)
	_expect(controller._corrosion._clouds.is_empty(), "权威到期快照清理残留")
	controller.apply_corrosion_snapshot(snapshot, player)
	controller.clear()
	_expect(controller._corrosion._clouds.is_empty() and controller.active_projectile_count() == 0, "切图清空喷吐和附着")
	# 使用真实配置速度验证客户端五帧进度，而非在渲染层再次乘40%。
	var slowed := {"attack_id": "gel.slow", "attack_archetype": "corrosive_projectile", "combat_actor_id": "toxic_gel_cold",
		"origin": [0, 0], "target_position": [400, 0], "projectile_speed": 400}
	_expect(controller.present_attack(slowed), "降速事件创建喷吐")
	var flight: CorrosiveEffectController.Flight = controller._corrosion._flights["gel.slow"]
	_expect(is_equal_approx(flight.duration, 1.0), "400像素距离以400像素每秒播放一秒")
	controller.advance(0.4)
	_expect(not flight.settled and controller.active_projectile_count() == 1, "旧速度已经到达的时刻仍在喷射")
	controller.advance(0.6)
	_expect(flight.settled and is_equal_approx(flight.fade_elapsed, 0.0), "喷射完成才开始三秒消散")
	controller.advance(2.9)
	_expect(controller._corrosion._flights.has("gel.slow"), "自然到达也保留完整三秒尾迹")
	controller.advance(0.11)
	_expect(controller._corrosion._flights.is_empty(), "自然到达的尾迹按时释放")
	controller.clear()


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
