extends SceneTree

var checks := 0
var failures: Array[String] = []


## 等待场景树完成初始化，再验证真实怪物与发生器动画。
func _initialize() -> void:
	call_deferred("_run")


## 检查原版帧、重复快照、移动跟随、到期清除和共享纹理；可输出实际OpenGL渲染。
func _run() -> void:
	root.size = Vector2i(900, 460)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/equipment_world/combat_visual_manifest.json"))
	var world := Node2D.new()
	root.add_child(world)
	var backdrop := ColorRect.new()
	backdrop.color = Color("827b60")
	backdrop.size = Vector2(900, 460)
	backdrop.z_index = -10
	world.add_child(backdrop)
	var player := Node2D.new()
	world.add_child(player)
	var controller := MonsterWorldController.new()
	root.add_child(controller)
	_check(controller.configure(world, manifest, player) == OK, "完整表现控制器")
	var snapshot := {"local_entity_id": "player", "monsters": [
		_monster("heat", 170, ["heat"]), _monster("corrosion", 450, ["corrosion"]), _monster("magnetism", 730, ["magnetism"]),
		_monster("idle", 1000, [])], "recent_events": []}
	controller.apply_snapshot(snapshot)
	var heat: MonsterWorldView = controller._views.heat
	var acid: MonsterWorldView = controller._views.corrosion
	var magnet: MonsterWorldView = controller._views.magnetism
	_check((controller._views.idle as MonsterWorldView).generator_status == null, "无状态怪物不创建额外节点")
	for view: MonsterWorldView in [heat, acid, magnet]:
		_check(view.generator_status != null and view.generator_status._active.size() == 1, "创建真实状态动画")
		view.generator_status.advance(0.16)
		var effect: GeneratorStatusView.Effect = view.generator_status._active.values()[0]
		_check(effect.sprite.get_parent() == view.generator_status and effect.sprite.position == Vector2(-5, -5), "原版挂载偏移")
		_check(effect.frames.size() in [7, 8, 9] and effect.sprite.texture == effect.frames[2].texture, "80ms原版帧速度")
		_check(view.generator_status._label.position.y > view.health_bar.position.y, "状态文字不遮挡血条和名字")
		view.set_hovered(true)
	var elapsed: float = heat.generator_status._active.heat.elapsed
	controller.apply_snapshot(snapshot)
	_check(heat.generator_status._active.heat.elapsed == elapsed, "重复快照不重置动画")
	var offset: Vector2 = heat.generator_status._active.heat.sprite.global_position - heat.global_position
	snapshot.monsters[0].position = [190, 260]
	controller.apply_snapshot(snapshot)
	_check(heat.generator_status._active.heat.sprite.global_position - heat.global_position == offset, "移动跟随而无历史位置漂移")
	if "--capture" in OS.get_cmdline_user_args():
		for view: MonsterWorldView in [heat, acid, magnet]: view.set_process(false)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/generator-status-effects.png")
	var shared_texture: Texture2D = heat.generator_status._active.heat.frames[0].texture
	snapshot.monsters[1].generator_statuses = ["heat", "heat", "unknown"]
	controller.apply_snapshot(snapshot)
	_check(acid.generator_status._active.size() == 1 and acid.generator_status._active.heat.frames[0].texture == shared_texture, "去重和共享纹理，不回退未知特效")
	snapshot.monsters[0].generator_statuses = []
	snapshot.monsters[1].alive = false
	controller.apply_snapshot(snapshot)
	_check(heat.generator_status._active.is_empty() and not heat.generator_status._label.visible, "状态到期清除")
	_check(acid.generator_status._active.is_empty() and not acid.visible, "死亡清除")
	controller.clear()
	controller.queue_free()
	world.queue_free()
	await process_frame
	print("Generator status view: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 生成真实奥姆虫表现可消费的状态快照。
## [param id] 当前怪物身份。
## [param x] 屏幕横向落点。
## [param effects] 服务器已生效的状态。
## 返回独立快照。
func _monster(id: String, x: int, effects: Array) -> Dictionary:
	return {"entity_id": id, "species_id": "om_adult", "display_name": "奥姆虫", "combat_actor_id": "om_adult_standard",
		"position": [x, 260], "health": 60, "max_health": 100, "alive": true, "action": "idle", "facing_index": 0,
		"generator_statuses": effects}


## 记录表现检查。
## [param condition] 实际条件。
## [param label] 失败说明。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
