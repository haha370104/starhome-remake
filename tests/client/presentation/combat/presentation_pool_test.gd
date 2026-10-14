extends SceneTree

var checks := 0
var failures: Array[String] = []


## 等待节点入树后检查表现池的实体隔离和生命周期。
func _initialize() -> void:
	call_deferred("_run")


## 复用同外观怪物及结束飘字，确认不泄漏旧实体数据。
func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/equipment_world/combat_visual_manifest.json"))
	var view := MonsterWorldView.new()
	world.add_child(view)
	_check(view.configure(manifest, _monster("old")) == OK, "创建旧怪物")
	view.set_hovered(true)
	var name_node := view.name_label
	var monster_pool := MonsterViewPool.new()
	monster_pool.recycle(view)
	_check(not view.visible and not view.name_label.visible and view.entity_id.is_empty(), "回收清除实体及悬浮")
	_check(monster_pool.take("different") == null, "不同外观不能复用")
	var reused := monster_pool.take("om_adult_standard")
	_check(reused == view, "同外观复用节点")
	reused.reuse(_monster("new"))
	_check(reused.entity_id == "new" and reused.name_label == name_node and reused.visible, "保留UI节点并绑定新实体")
	_check(not reused.name_label.visible and reused._last_action_sequence == 0, "新实体无旧悬浮或动作代际")
	var damage_pool := DamageFloatPool.new()
	root.add_child(damage_pool)
	damage_pool.configure(world)
	var first := damage_pool.take()
	first.present(5)
	var label := first._label
	var other := damage_pool.take()
	_check(first != other, "活动飘字不能被抢占")
	first.cancel()
	first._finish()
	var second := damage_pool.take()
	second.present_status("+10", Color.GREEN)
	_check(second == first and second._label == label, "复用已完成节点和Label")
	_check(second._label.text == "+10" and second._label.modulate.a == 1.0, "重置文字及透明度")
	damage_pool.clear()
	monster_pool.recycle(reused)
	monster_pool.clear()
	await process_frame
	_check(not is_instance_valid(first) and not is_instance_valid(view), "切图释放池中引用")
	damage_pool.queue_free()
	world.queue_free()
	await process_frame
	print("Presentation pools: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 构造正式表现配置可消费的怪物状态。
## [param identity] 测试实体ID。
## 返回完整外观和动作快照。
func _monster(identity: String) -> Dictionary:
	return {"entity_id": identity, "combat_actor_id": "om_adult_standard", "position": [100, 200],
		"alive": true, "health": 60, "max_health": 60, "display_name": identity,
		"facing_index": 2, "action": "idle", "action_sequence": 0}


## 汇总表现状态隔离断言。
## [param condition] 实际结果。[param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
