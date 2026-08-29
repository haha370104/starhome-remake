extends SceneTree

const MainHallScene := preload("res://scenes/main_hall.tscn")

var failures: PackedStringArray = []
var assertions := 0


## 延迟运行需要大厅节点树完成 `_ready` 的客户端状态接缝测试。
func _initialize() -> void:
	call_deferred("_run")


## 组合验证权威校正的路线策略，以及预载失败前后的旧地图隔离状态。
## 设计：成功切图的原子替换已由 `map_transition_scene_smoke_test` 覆盖，本夹具只补其失败分支与移动接缝。
func _run() -> void:
	await _test_route_policy_after_authoritative_correction()
	await _test_pre_authority_preload_failure_keeps_old_world_active()
	await _test_post_authority_preload_failure_locks_old_world()
	_expect(assertions >= 28, "组合夹具必须完成全部三个场景，脚本加载或异步异常不得伪装成通过")
	_finish()


## 验证小校正从新位置重算旧目标路线，强制校正则彻底取消旧路线与输入序号。
func _test_route_policy_after_authoritative_correction() -> void:
	var hall := await _create_hall()
	var target := _find_route_target(hall)
	_expect(target.is_finite(), "测试地图必须提供一条可行旧路线")
	if not target.is_finite():
		hall.free()
		return
	hall.call("_move_to", target)
	var original_path: PackedVector2Array = hall.path_points.duplicate()
	var corrected_position := _find_small_correction_with_distinct_path(hall, target, original_path)
	_expect(corrected_position.is_finite(), "必须找到不超过平滑阈值且会改变路线起点的可走位置")
	if corrected_position.is_finite():
		var expected_replanned: PackedVector2Array = hall.navigation.find_path(corrected_position, target)
		hall.call("_on_multiplayer_local_character_state_applied", {
			"position": corrected_position,
			"correction_mode": &"smooth",
		})
		_expect_path(
			hall.path_points,
			expected_replanned,
			"平滑权威校正必须保留目标并从校正位置重算路线",
		)
		_expect(hall.movement_click_effects.active_effect_count() == 0, "权威校正不得生成鼠标落点反馈")

	# Re-establish a route so the forced correction assertion is independent from
	# the small-correction result above.
	hall.call("_move_to", target)
	_expect(not hall.path_points.is_empty(), "强制校正前必须存在活动路线")
	var forced_position: Vector2 = hall.navigation.closest_reachable_position(
		hall.player.position,
		hall.player.position + Vector2(180.0, 120.0),
	)
	hall.call("_on_multiplayer_local_character_state_applied", {
		"position": forced_position,
		"correction_mode": &"forced",
	})
	_expect(hall.path_points.is_empty(), "强制权威校正必须取消旧地图路线")
	_expect(hall.active_movement_input_sequence == 0, "强制权威校正必须清除旧移动输入序号")
	_expect(hall.movement_click_effects.active_effect_count() == 0, "强制权威校正不得生成鼠标落点反馈")
	hall.free()


## 验证权威请求提交前的预载失败保留旧地图、旧会话，并恢复该地图输入。
func _test_pre_authority_preload_failure_keeps_old_world_active() -> void:
	var hall := await _create_hall()
	var old_map_id: StringName = hall.map_definition.map_id
	var old_instance_id: String = hall.multiplayer_presenter.session.current_map_instance_id
	var old_floor: Texture2D = hall.map_background.texture
	var old_navigation: RefCounted = hall.navigation
	var old_npc_count: int = hall.npc_instances.size()
	hall.pending_map_transition = {
		"transition_id": &"review_missing_exit",
		"destination_map_id": &"g08_field_zone",
	}
	hall.call("_on_map_preload_failed", &"g08_field_zone", "测试资源缺失")
	_expect(hall.pending_map_transition.is_empty(), "请求前预载失败必须清空暂存切图")
	_expect(not hall.call("_world_input_locked"), "请求前预载失败必须恢复旧地图输入")
	_expect(hall.map_definition.map_id == old_map_id, "请求前预载失败必须保留旧活动地图")
	_expect(hall.map_background.texture == old_floor, "请求前预载失败必须保留旧地图画面")
	_expect(hall.navigation == old_navigation, "请求前预载失败必须保留旧导航实例")
	_expect(hall.npc_instances.size() == old_npc_count, "请求前预载失败必须保留旧地图实体")
	_expect(hall.multiplayer_presenter.session.current_map_id == old_map_id, "请求前预载失败必须保留旧会话地图")
	_expect(hall.multiplayer_presenter.session.current_map_instance_id == old_instance_id, "请求前预载失败必须保留旧会话实例")
	var before_sequence: int = hall.multiplayer_presenter.session.local_predictor.next_input_sequence
	var target := _find_route_target(hall)
	if target.is_finite():
		hall.call("_move_to", target)
	_expect(
		hall.multiplayer_presenter.session.local_predictor.next_input_sequence == before_sequence + 1,
		"请求前预载失败后应能继续向旧会话提交移动",
	)
	hall.free()


## 验证会话已接受 `map_joined` 后的本地预载失败保留旧画面但永久冻结其输入。
## 设计：服务端权威身份不可回滚；客户端只能保留旧画面作诊断并锁输入，等待重连或恢复资源。
func _test_post_authority_preload_failure_locks_old_world() -> void:
	var hall := await _create_hall()
	var old_map_id: StringName = hall.map_definition.map_id
	var old_floor: Texture2D = hall.map_background.texture
	var old_navigation: RefCounted = hall.navigation
	var old_npc_count: int = hall.npc_instances.size()
	var session = hall.multiplayer_presenter.session
	session.current_map_id = &"g08_field_zone"
	session.configure_map_instance("g08_field_zone.instance.review")
	var before_sequence: int = session.local_predictor.next_input_sequence
	hall.call(
		"_on_authoritative_map_joined",
		&"g08_field_zone",
		"g08_field_zone.instance.review",
		Vector2(420.0, 520.0),
		1,
	)
	_expect(hall.map_definition.map_id == old_map_id, "权威后预载失败必须保留旧活动画面身份")
	_expect(hall.map_background.texture == old_floor, "权威后预载失败必须保留旧底图")
	_expect(hall.navigation == old_navigation, "权威后预载失败不得半提交新导航")
	_expect(hall.npc_instances.size() == old_npc_count, "权威后预载失败不得半清理旧地图实体")
	_expect(hall.map_commit_failure_locked, "权威后预载失败必须进入不可恢复锁定状态")
	_expect(hall.call("_world_input_locked"), "权威后预载失败必须冻结旧画面输入")
	_expect(hall.path_points.is_empty(), "权威后预载失败必须终止旧路线")
	_expect(hall.active_movement_input_sequence == 0, "权威后预载失败必须清除旧输入序号")
	_expect(session.current_map_id == &"g08_field_zone", "权威会话地图必须保持服务端已提交目标")
	_expect(session.current_map_instance_id == "g08_field_zone.instance.review", "权威会话实例必须保持服务端已提交目标")
	hall.call("_move_to", hall.player.position + Vector2(32.0, 0.0))
	_expect(
		session.local_predictor.next_input_sequence == before_sequence,
		"锁定旧画面不得向新会话创建移动输入",
	)
	hall.free()


## 创建完成 `_ready` 的大厅并暂停其逐帧行走，供接缝状态做确定性断言。
## 返回该函数计算、查询或操作得到的结果。
func _create_hall() -> Node2D:
	var hall: Node2D = MainHallScene.instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	await process_frame
	hall.set_process(false)
	return hall


## 执行 `find_route_target` 对应的模块操作。
## [param hall] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _find_route_target(hall: Node2D) -> Vector2:
	var origin: Vector2 = hall.player.position
	var offsets := [
		Vector2(240.0, 0.0),
		Vector2(-240.0, 0.0),
		Vector2(0.0, 240.0),
		Vector2(0.0, -240.0),
		Vector2(180.0, 180.0),
	]
	for offset in offsets:
		var candidate: Vector2 = hall.navigation.closest_reachable_position(origin, origin + offset)
		var route: PackedVector2Array = hall.navigation.find_path(origin, candidate)
		if candidate.is_finite() and route.size() > 1:
			return candidate
	return Vector2(INF, INF)


## 执行 `find_small_correction_with_distinct_path` 对应的模块操作。
## [param hall] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param target] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param original_path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _find_small_correction_with_distinct_path(
	hall: Node2D,
	target: Vector2,
	original_path: PackedVector2Array,
) -> Vector2:
	var origin: Vector2 = hall.player.position
	var offsets := [
		Vector2(16.0, 0.0),
		Vector2(-16.0, 0.0),
		Vector2(0.0, 16.0),
		Vector2(0.0, -16.0),
		Vector2(12.0, 12.0),
		Vector2(-12.0, 12.0),
	]
	for offset in offsets:
		var candidate: Vector2 = origin + offset
		if not hall.navigation.is_walkable(candidate):
			continue
		var replanned: PackedVector2Array = hall.navigation.find_path(candidate, target)
		if not replanned.is_empty() and not _paths_equal(replanned, original_path):
			return candidate
	return Vector2(INF, INF)


## 执行 `expect_path` 对应的模块操作。
## [param actual] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param expected] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_path(
	actual: PackedVector2Array,
	expected: PackedVector2Array,
	message: String,
) -> void:
	_expect(_paths_equal(actual, expected), "%s (actual=%s expected=%s)" % [message, actual, expected])


## 执行 `paths_equal` 对应的模块操作。
## [param left] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param right] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _paths_equal(left: PackedVector2Array, right: PackedVector2Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if not left[index].is_equal_approx(right[index]):
			return false
	return true


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出组合测试汇总，并根据累计失败数量设置退出码。
func _finish() -> void:
	if failures.is_empty():
		print("CLIENT STATE SEAM CHARACTERIZATION OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"CLIENT STATE SEAM CHARACTERIZATION FAILED (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)
