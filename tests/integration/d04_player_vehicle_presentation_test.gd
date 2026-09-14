extends SceneTree

const MainHallScene := preload("res://scenes/main_hall.tscn")
const CITY_DEFINITION := "res://data/maps/yian_harbor_city.json"
const D04_DEFINITION := "res://data/maps/d04_field_zone.json"
const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")

var assertions := 0
var failures: PackedStringArray = []


## 延迟执行大厅、城区、D04 的玩家外观切换回归。
func _initialize() -> void:
	call_deferred("_run")


## 依次提交真实地图 bundle，验证 D04 只显示荣耀版八向新兵战车。
func _run() -> void:
	var hall: Node2D = MainHallScene.instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	await process_frame
	var player: Node2D = hall.world_view.player
	_expect(hall.world_view.camera.zoom == Vector2.ONE, "世界摄像机必须保持原客户端 1:1 像素比例")
	_expect(player.presentation_kind == &"character", "大厅出生必须保持人形玩家")
	_expect(player.human_character.visible, "大厅必须显示人形合成层")
	_expect(
		player.human_character.name_label.position
		== player.HUMAN_NAME_LABEL_POSITION,
		"人形昵称必须贴近原客户端脚点上方 82 像素的文字锚点",
	)
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
	_expect(
		player.combat_name_label.position == player.COMBAT_NAME_LABEL_POSITION,
		"战车昵称必须贴近原客户端脚点上方 42 像素的文字锚点",
	)
	_expect(player.combat_presenter.get_child_count() == 5, "战车应预载三种武器层并只显示当前模式")
	_expect(player.combat_presenter._layers[&"primary_weapon"].visible, "默认应显示能量炮层")
	_expect(not player.combat_presenter._layers[&"missile_weapon"].visible, "未选择时应隐藏导弹层")
	hall.call("_on_weapon_slot_selected", "missile")
	_expect(player.combat_presenter._layers[&"missile_weapon"].visible, "选择导弹后应切换场景装备层")
	hall.call("_on_weapon_slot_selected", "energy_cannon")
	_expect(player.combat_status_bar.position == Vector2(0, 45), "战车状态条应复原原客户端脚点下方 45 像素锚点")
	_expect(is_equal_approx(player.combat_status_bar._bar_width, 50.0), "战车状态条应复原原客户端 50 像素宽度")
	_expect(is_equal_approx(player.combat_status_bar._energy_offset_y, 4.0), "能量条应紧接生命条下方四像素")
	_test_eight_way_idle_and_move(player, hall.local_player_controller)
	_test_move_and_fire_keeps_route(hall)
	_test_evidence_contract(d04_definition, player.combat_presenter)
	_test_equipped_vehicle_replaces_map_placeholder(player)
	_test_cannon_mining_click_is_rejected(hall)
	_test_engineering_arm_empty_click(hall)

	_expect(
		hall.active_world_controller.commit_bundle(city_bundle, Vector2(1399, 954)),
		"从 D04 返回城区必须仍可提交",
	)
	_expect(player.presentation_kind == &"character", "返回城区必须恢复人形而非残留战车")
	_expect(player.human_character.visible and not player.combat_presenter.visible, "两套表现必须互斥")
	_finish(hall)


## 验证地图仅声明战车模式，实际底盘与主炮由当前 PlayerVehicle 装配覆盖。
## [param player] 当前 D04 玩家世界 avatar。
func _test_equipped_vehicle_replaces_map_placeholder(player: Node2D) -> void:
	var catalog: ItemCatalog = ItemCatalogScript.new()
	var initialized := catalog.initialize()
	_expect(initialized.is_ok, "实际战车外观测试应加载统一物品目录")
	if not initialized.is_ok:
		return
	var vehicle := PlayerVehicle.new({
		"vehicle_id": "vehicle.presentation.test",
		"definition_id": "recruit_tank",
		"max_health": 70,
		"health": 70,
		"reserve_energy_capacity": 10000.0,
		"reserve_energy": 10000.0,
		"working_energy_capacity": 100.0,
		"working_energy": 100.0,
		"output_power": 21.0,
	})
	for definition_id: String in [
		"glory_equipment_tank1000_27ae5e8059",
		"glory_equipment_gun1000_c4c24e2500",
	]:
		var created := catalog.create(definition_id, {
			"instance_id": "presentation.%s" % definition_id,
			"footprint_px": [45, 45],
		})
		_expect(created.is_ok and vehicle.loadout.restore(created.value).is_ok,
			"撒玛王底盘与天神之怒应进入固定装配")
	vehicle.reconcile_loadout_state()
	_expect(player.apply_vehicle_equipment(vehicle),
		"世界 avatar 应接受当前玩家实际战车装配")
	_expect(player.combat_actor_id == &"equipped_combat_vehicle",
		"D04 世界外观必须切换为由实际固定装配动态合成的 actor")
	_expect(
		player.combat_presenter._actor.get("installed_components", []) == [
			"sama_king_vehicle_chassis", "divine_wrath_energy_cannon",
		],
		"动态 actor 必须分别消费撒玛王底盘与天神之怒主炮",
	)
	_expect(player.combat_presenter.layer_frame(&"chassis") >= 0,
		"撒玛王底盘应完成实际帧渲染")
	_expect(player.combat_presenter.layer_frame(&"primary_weapon") >= 0,
		"天神之怒主炮应完成实际帧渲染")
	var config := JsonConfigLoader.load_dictionary("res://data/gameplay/commerce/weapon_merchant_v1.json")
	for definition_id: String in config.value.merchant.official_whitelist_ids.mining_arm:
		var created := catalog.create(definition_id, {"instance_id": "presentation.arm"})
		_expect(created.is_ok and created.value is VehicleMiningArm, "商人采掘臂应构造为工程臂模型")
		if not created.is_ok:
			continue
		vehicle.loadout.equip(created.value, 1, vehicle.loadout.revision)
		_expect(player.apply_vehicle_equipment(vehicle), "采掘臂换装应更新真实场景模型")
		var installed: Array = player.combat_presenter._actor.installed_components
		_expect(String(installed[1]).begins_with("mining_arm_level_"), "采掘臂不得残留上一把能量炮贴图")
		_expect(player.combat_presenter.layer_frame(&"primary_weapon") >= 0, "采掘臂八向资源应可渲染")
		_test_mining_animation(player)


## 验证所有在售采掘臂真正推进八向帧，而非仅加载第一张静态贴图。
## [param player] 已装配当前采掘臂的世界表现节点。
func _test_mining_animation(player: Node2D) -> void:
	var controller = preload("res://scripts/client/presentation/mining/mining_visual_controller.gd").new()
	controller.configure(player)
	player.set_action("stand", 0)
	var actions: Dictionary = player.combat_presenter._layer_configs[&"primary_weapon"].actions
	_expect(is_equal_approx(float(actions.collect.fps), 1000.0 / 60.0), "采掘臂按原脚本 60ms 帧间隔播放，不沿用默认 10fps")
	for direction: int in range(8):
		var target: Vector2 = player.position + Vector2.RIGHT.rotated(-direction * PI / 4.0) * 40.0
		var snapshot := {"local_vehicle": {"health": 70}, "local_mining": {
			"active": true, "source_id": "test.mine", "target_position": [target.x, target.y],
		}}
		controller.apply_snapshot(snapshot)
		var first: int = player.combat_presenter.layer_frame(&"primary_weapon")
		# 重复的待机姿态和权威快照不能每帧把采矿动画重置到首帧。
		for tick: int in range(4):
			player.set_action("stand", 0)
			controller.apply_snapshot(snapshot)
			player.combat_presenter.advance(0.05)
		var last: int = player.combat_presenter.layer_frame(&"primary_weapon")
		_expect(first != last, "方向 %d 采矿动画必须实际变化" % direction)
		_expect(player.combat_presenter._layer_direction_overrides[&"primary_weapon"] == direction,
			"采掘臂应面向矿物且不改变车身朝向")
		controller.apply_snapshot({"local_mining": {"active": false}})
		first = player.combat_presenter.layer_frame(&"primary_weapon")
		player.combat_presenter.advance(0.2)
		_expect(first == player.combat_presenter.layer_frame(&"primary_weapon"), "停采后必须恢复静态帧")
		_expect(not player.combat_presenter._layer_direction_overrides.has(&"primary_weapon"), "停采必须释放局部朝向")
	controller.clear()


## 验证真实大厅采矿入口在能量炮装配下给出拒绝提示，不发送采矿意图。
## [param hall] 已初始化界面和客户端会话的大厅场景。
func _test_cannon_mining_click_is_rejected(hall: Node2D) -> void:
	var catalog := ItemCatalogScript.new()
	_expect(catalog.initialize().is_ok, "点击测试物品目录初始化")
	var current: CurrentPlayer = hall.panel_session.current_player
	current.vehicle.loadout = VehicleLoadout.new()
	for definition_id: String in ["glory_equipment_tank1000_27ae5e8059", "glory_equipment_gun1000_c4c24e2500"]:
		var created := catalog.create(definition_id, {"instance_id": "click.%s" % definition_id})
		_expect(created.is_ok and current.vehicle.loadout.restore(created.value).is_ok, "装配点击测试车炮")
	hall._request_mining(Vector2(1200, 1200))
	_expect(hall.hud.status_text().contains("能量炮不能采矿"), "真实矿物点击入口应立即中文拒绝，不能显示正在准备采矿")
	_expect(hall.world_view.player.apply_vehicle_equipment(current.vehicle), "点击测试应同步真实炮的外观")
	hall.world_view.mining_visual_controller.apply_snapshot({"local_vehicle": {"health": 70}, "local_mining": {
		"active": true, "target_position": [0.0, 100.0],
	}})
	_expect(not hall.world_view.player.combat_presenter._layer_action_overrides.has(&"primary_weapon"),
		"陈旧的活动快照也不得让能量炮播放采矿")
	_expect(not hall.world_view.player.combat_presenter._layer_direction_overrides.has(&"primary_weapon"),
		"拒绝不支持的采矿动画时不能遗留炮管朝向覆盖")


## 执行 `test_eight_way_idle_and_move` 对应的模块操作。
## [param player] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param controller] 调用方传入的参数；具体约束由函数签名和所在模块定义。
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


## 执行 `test_move_and_fire_keeps_route` 对应的模块操作。
## [param hall] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _test_move_and_fire_keeps_route(hall: Node2D) -> void:
	var origin: Vector2 = hall.world_view.player.position
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
	_expect(hall.world_view.combat_attack_controller.active_projectile_count() == 1, "移动中开火仍须生成弹体")


## 验证真实目录构建的工程臂空地点击静默，不产生弹体，也不提交网络能力意图。
## [param hall] 已完成 D04 装配的真实大厅场景。
func _test_engineering_arm_empty_click(hall: Node2D) -> void:
	var catalog := ItemCatalogScript.new()
	_expect(catalog.initialize().is_ok, "工程臂点击测试初始化目录")
	var current: CurrentPlayer = hall.panel_session.current_player
	var vehicle := current.vehicle
	var original_loadout := vehicle.loadout
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gameplay/commerce/weapon_merchant_v1.json"))
	var projectile_count: int = hall.world_view.combat_attack_controller.active_projectile_count()
	var ability_sequence: int = hall.multiplayer_presenter.session._next_ability_sequence
	var feed: CentralSystemMessageFeed = hall.hud.system_message_feed
	var message_count := feed.queued_message_count()
	var active_message := feed.message_label.text
	hall.hud.state.set_selected_action_slot("energy_cannon")
	for device_kind: String in ["mining_arm", "repair_arm"]:
		for definition_id: String in config.merchant.official_whitelist_ids[device_kind]:
			var created := catalog.create(definition_id, {"instance_id": "click.engineering"})
			_expect(created.is_ok and created.value is VehicleEquipment and not created.value is VehicleWeapon,
				"所有在售工程臂都不应构造成射击武器")
			vehicle.loadout = VehicleLoadout.new()
			_expect(vehicle.loadout.restore(created.value).is_ok, "工程臂可安装到主槽")
			_expect(created.value.primary_device_kind() == device_kind, "模型应提供正确主槽类型")
			hall._on_current_player_changed(current)
			_expect(hall.hud.state.primary_device_kind == device_kind, "当前玩家快照绑定必须刷新主槽图标")
			hall.hud.show_status("原提示保持不变")
			# 空图外坐标不包含矿物、掉落或怪物；若误入发射链将产生弹体或连接错误。
			hall._handle_world_combat_left_click(Vector2(-10000, -10000))
			_expect(hall.hud.status_text() == "原提示保持不变", "空地点击不显示任何错误")
			_expect(feed.queued_message_count() == message_count and feed.message_label.text == active_message,
				"空地点击不能向中央消息队列添加错误")
			_expect(hall.multiplayer_presenter.session._next_ability_sequence == ability_sequence,
				"空地点击不得提交开炮意图")
			_expect(hall.world_view.combat_attack_controller.active_projectile_count() == projectile_count, "工程臂不产生炮弹")
	vehicle.loadout = original_loadout
	hall._on_current_player_changed(current)


## 执行 `test_evidence_contract` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param presenter] 调用方传入的参数；具体约束由函数签名和所在模块定义。
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
	var chassis_actions: Dictionary = {}
	for raw_layer: Variant in layers:
		var layer: Dictionary = raw_layer
		if StringName(layer.get("id", "")) == &"chassis":
			chassis_actions = layer.get("actions", {})
	_expect(
		String((chassis_actions["idle"] as Dictionary).get("resource", ""))
		== String((chassis_actions["move"] as Dictionary).get("resource", "")),
		"idle 与 move 必须诚实复用同一荣耀底盘资源",
	)
	_expect(float((chassis_actions["idle"] as Dictionary).get("fps", -1.0)) == 0.0, "idle 必须停在方向首帧")
	_expect(float((chassis_actions["move"] as Dictionary).get("fps", 0.0)) == 10.0, "move 必须采用来源清单帧率")


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 执行 `finish` 对应的模块操作。
## [param hall] 调用方传入的参数；具体约束由函数签名和所在模块定义。
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
