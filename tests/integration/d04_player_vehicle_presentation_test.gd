extends SceneTree

const MainHallScene := preload("res://scenes/main_hall.tscn")
const CITY_DEFINITION := "res://data/maps/yian_harbor_city.json"
const D04_DEFINITION := "res://data/maps/d04_field_zone.json"

var assertions := 0
var failures: PackedStringArray = []


## 延迟执行大厅、城区、D04 的玩家外观切换回归。
func _initialize() -> void:
	call_deferred("_run")


## 依次提交真实地图 bundle，验证 D04 只显示荣耀版八向新兵战车。
func _run() -> void:
	var hall: Node2D = MainHallScene.instantiate()
	root.add_child(hall)
	await process_frame
	await process_frame
	var player: Node2D = hall.player
	_expect(player.presentation_kind == &"character", "大厅出生必须保持人形玩家")
	_expect(player.human_character.visible, "大厅必须显示人形合成层")
	_expect(not player.combat_presenter.visible, "大厅不得提前显示战车")

	var city_bundle: Dictionary = hall.active_world_controller.prepare_initial_bundle(CITY_DEFINITION)
	_expect(not city_bundle.is_empty(), "城区 bundle 必须可预载")
	_expect(
		hall.active_world_controller.commit_bundle(city_bundle, Vector2(1399, 954)),
		"大厅到城区的真实 bundle 必须可提交",
	)
	_expect(player.presentation_kind == &"character", "城区继续显示人形玩家")

	var d04_bundle: Dictionary = hall.active_world_controller.prepare_initial_bundle(D04_DEFINITION)
	_expect(not d04_bundle.is_empty(), "D04 bundle 必须可预载")
	var d04_definition: MapDefinition = d04_bundle.get("definition")
	var d04_spawn: MapSpawnPoint = d04_definition.spawn_for_entry(1)
	_expect(d04_spawn != null, "D04 必须存在来自城区入口 1 的出生点")
	if d04_spawn != null:
		_expect(
			hall.active_world_controller.commit_bundle(d04_bundle, d04_spawn.position),
			"城区到 D04 的真实 bundle 必须可提交",
		)
		_expect(player.position == d04_spawn.position, "战车与玩家脚点必须共享 D04 权威出生坐标")

	_expect(player.presentation_kind == &"combat_actor", "D04 玩家必须切换为战斗载具")
	_expect(player.combat_actor_id == &"starter_combat_vehicle", "D04 必须选择业务化新兵战车")
	_expect(not player.human_character.visible, "D04 不得把人形层叠在战车下方")
	_expect(player.combat_presenter.visible, "D04 必须显示战车表现器")
	_expect(player.combat_name_label.visible, "战车模式仍须保留玩家名称")
	_expect(player.combat_presenter.get_child_count() == 2, "战车仅叠底盘和能量炮两个世界层")
	_test_eight_way_idle_and_move(player, hall.local_player_controller)
	_test_move_and_fire_keeps_route(hall)
	_test_evidence_contract(d04_definition, player.combat_presenter)

	_expect(
		hall.active_world_controller.commit_bundle(city_bundle, Vector2(1399, 954)),
		"从 D04 返回城区必须仍可提交",
	)
	_expect(player.presentation_kind == &"character", "返回城区必须恢复人形而非残留战车")
	_expect(player.human_character.visible and not player.combat_presenter.visible, "两套表现必须互斥")
	_finish(hall)


## 验证 [param player] 的八向静止首帧和移动四帧，不依赖截图判断方向。
## [param controller] 提供正式方向量化与动作入口。
func _test_eight_way_idle_and_move(player: Node2D, controller: Node) -> void:
	for direction in range(8):
		player.set_action("stand", direction)
		_expect(
			player.combat_presenter.layer_frame(&"chassis") == direction * 4,
			"每个静止朝向必须固定使用对应四帧块的首帧",
		)
		_expect(
			player.combat_presenter.layer_frame(&"primary_weapon") == direction,
			"能量炮必须使用与底盘一致的八向索引",
		)
	player.set_action("move", 3)
	player.combat_presenter.advance(0.21)
	_expect(player.combat_presenter.layer_frame(&"chassis") == 14, "移动应在西北方向四帧块内推进")
	_expect(player.combat_presenter.layer_frame(&"primary_weapon") == 3, "单帧炮管移动时保持同方向")
	_expect(controller.direction_index(Vector2.RIGHT) == 0, "正式移动控制器右向必须映射 east")
	_expect(controller.direction_index(Vector2(-1, -1)) == 3, "正式移动控制器左上必须映射 north_west")


## 验证 [param hall] 的战车在活动寻路中开火不会取消剩余路线或预测移动。
func _test_move_and_fire_keeps_route(hall: Node2D) -> void:
	var origin: Vector2 = hall.player.position
	var requested_target := origin + Vector2(180, 90)
	var movement_target: Vector2 = hall.navigation.closest_reachable_position(
		origin,
		requested_target,
	)
	_expect(movement_target.is_finite(), "D04 出生点附近必须能解析移动目标")
	if not movement_target.is_finite():
		return
	var movement_result: Dictionary = hall.local_player_controller.request_move(movement_target)
	_expect(bool(movement_result.get("ok", false)), "战车必须先建立未完成路线")
	var route_before_fire: PackedVector2Array = hall.path_points.duplicate()
	hall._handle_world_combat_left_click(origin + Vector2(120, 0))
	_expect(hall.local_player_controller.has_active_route(), "开火不得停止活动路线")
	_expect(hall.path_points == route_before_fire, "开火不得改写尚未完成的路径折线")
	_expect(hall.combat_attack_controller.active_projectile_count() == 1, "移动中开火仍须生成弹体")


## 验证 [param definition] 与 [param presenter] 没有虚构独立 idle 资源。
func _test_evidence_contract(definition: MapDefinition, presenter: Node2D) -> void:
	var map_evidence: Dictionary = definition.player_presentation.get("animation_evidence", {})
	_expect(
		String(map_evidence.get("directional_coverage", "")) == "source_confirmed_eight_way",
		"D04 必须声明八向素材为来源确认",
	)
	_expect(
		String(map_evidence.get("idle_cycle", "")) == "reconstructed_directional_first_frame",
		"D04 必须显式声明 idle 是方向首帧重建策略",
	)
	var actor: Dictionary = presenter._actor
	var actor_evidence: Dictionary = actor.get("animation_evidence", {})
	_expect(actor_evidence == map_evidence or not actor_evidence.is_empty(), "战车运行时清单必须保存动画证据")
	var layers: Array = actor.get("layers", [])
	var chassis_actions: Dictionary = (layers[0] as Dictionary).get("actions", {})
	_expect(
		String((chassis_actions["idle"] as Dictionary).get("resource", ""))
		== String((chassis_actions["move"] as Dictionary).get("resource", "")),
		"idle 与 move 必须诚实复用同一荣耀底盘资源",
	)
	_expect(float((chassis_actions["idle"] as Dictionary).get("fps", -1.0)) == 0.0, "idle 必须停在方向首帧")
	_expect(float((chassis_actions["move"] as Dictionary).get("fps", 0.0)) == 10.0, "move 必须采用来源清单帧率")


## 记录 [param condition]，失败时附带 [param message]。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出结果、释放 [param hall] 并结束测试进程。
func _finish(hall: Node2D) -> void:
	if failures.is_empty():
		print("D04_PLAYER_VEHICLE_PRESENTATION_OK (%d assertions)" % assertions)
		hall.free()
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	hall.free()
	quit(1)
