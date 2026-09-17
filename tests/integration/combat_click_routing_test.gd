extends SceneTree

class IntentProbe:
	extends HallMultiplayerPresenter
	var abilities: Array[String] = []
	var pickups: Array[String] = []

	## 捕获客户端发布的技能意图，不连接外部服务。
	## [param ability_id] 实际路由到的技能。
	## [param _position] 瞄准点。
	## 返回模拟已发送的输入序号。
	func request_use_ability(ability_id: String, _position: Vector2) -> Dictionary:
		abilities.append(ability_id)
		return {"input_sequence": abilities.size()}

	## 捕获优先拾取的权威掉落标识。
	## [param loot_id] 当前点击选中的地面实体。
	## 返回已发送的拾取请求。
	func request_loot_pickup(loot_id: String) -> Dictionary:
		pickups.append(loot_id)
		return {"loot_id": loot_id}

var checks := 0
var failures: Array[String] = []
var repairs: Array[Vector2] = []
var catalog := ItemCatalog.new()


## 延迟验证实际矿物、掉落和装备分发，使用隔离命令通道。
func _initialize() -> void:
	call_deferred("_run")


## 将矿物与掉落重叠摆放，验证原图、描边、名称及不同主装置的默认行为。
func _run() -> void:
	var hall: Node2D = load("res://scenes/main_hall.tscn").instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	await process_frame
	var active: ActiveWorldController = hall.active_world_controller
	var bundle := active.prepare_initial_bundle("res://data/maps/d04_field_zone.json")
	var definition: MapDefinition = bundle.definition
	_expect(active.commit_bundle(bundle, definition.spawn_for_entry(1).position), "提交实际野外战车地图")
	var probe := IntentProbe.new()
	hall.add_child(probe)
	hall.combat.bind_session(probe, hall.panel_session)
	hall.combat.target_repair_requested.connect(func(point: Vector2) -> void: repairs.append(point))
	_expect(catalog.initialize().is_ok, "装配目录可用")
	var current: Player = hall.panel_session.current_player
	current.skills = SkillBook.new({"mining": 700})
	var minerals: MineralWorldController = hall.world_view.mineral_world_controller
	var loot: GroundLootWorldController = hall.world_view.ground_loot_world_controller
	minerals.apply_snapshot({"mine_sources": [{"source_id": "overlap.mine", "mineral_id": "iron_ore",
		"position": [1200, 1200], "remaining": 50, "visual_variant": 3, "required_mining_level": 0}]})
	loot.apply_snapshot({"ground_loot": [{"loot_id": "overlap.loot", "item_definition_id": "low_grade_biosilicon",
		"quantity": 2, "position": [1200, 1200]}]})
	var view := loot.view_for_loot("overlap.loot")
	_expect(view != null and minerals.active_view_count() == 1, "真实掉落与矿物视图同时存在")
	var icon_point := view.to_global(view.local_hit_rect().get_center())
	var edge_point := view.to_global(view.local_hit_rect().position + Vector2(-2, 8))
	for equipment: String in ["glory_equipment_gun1000_c4c24e2500",
			"glory_equipment_collector_ac947ee094", "glory_equipment_repair_aab7d81665"]:
		_equip(current, equipment)
		for point: Vector2 in [icon_point, edge_point]:
			_expect(not minerals.source_at(point).is_empty(), "复现点同时落在矿物范围内")
			var before := probe.pickups.size()
			hall.combat.handle_world_combat_left_click(point)
			_expect(probe.pickups.size() == before + 1 and probe.pickups.back() == "overlap.loot",
				"不同主装置均优先拾取物品与描边")
	view.set_hovered(true)
	await process_frame
	var tooltip := view.get_node("HoverTooltip") as Label
	var name_point := view.to_global(tooltip.position + Vector2(4, 8))
	_expect(not view.contains_world_point(name_point) and not minerals.source_at(name_point).is_empty(),
		"复现名称位于原图外且与矿物重叠")
	var before := probe.pickups.size()
	hall.combat.handle_world_combat_left_click(name_point)
	_expect(probe.pickups.size() == before + 1, "点击可见物品名优先拾取，不能误判采矿")
	_expect(tooltip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "名称不会吞掉世界拾取输入")
	view.set_hovered(false)
	_expect(loot.loot_at(name_point).is_empty(), "名称隐藏后不保留不可见拾取区域")
	_expect(probe.abilities.is_empty() and repairs.is_empty(), "所有拾取均不会同时发出采矿、开火或维修")
	loot.remove_loot("overlap.loot")
	await process_frame
	var target := Vector2(1200, 1200)
	_equip(current, "glory_equipment_gun1000_c4c24e2500")
	hall.hud.select_action("energy_cannon")
	hall.combat.handle_world_combat_left_click(target)
	_expect(probe.abilities == ["energy_cannon.primary"], "能量炮点击矿物仍使用真实开炮流程")
	_equip(current, "glory_equipment_repair_aab7d81665")
	hall.combat.handle_world_combat_left_click(target)
	_expect(repairs == [target] and probe.abilities.size() == 1, "维修臂点击矿物只产生客户端维修意图")
	_expect(hall.hud.status_text().contains("维修") and not hall.hud.status_text().contains("采矿"), "维修反馈不误报采矿")
	_equip(current, "glory_equipment_collector_ac947ee094")
	hall.combat.handle_world_combat_left_click(target)
	_expect(probe.abilities.back() == "mining.collect" and probe.abilities.size() == 2, "采掘臂点击矿物才提交采矿")
	before = probe.abilities.size()
	hall.combat.handle_world_combat_left_click(Vector2(1600, 1600))
	_expect(probe.abilities.size() == before, "采掘臂点击空地不会发出开炮或采矿意图")
	hall.hud.set_tactical_action("rocket_launcher", 10)
	hall.hud.select_action("rocket_launcher")
	hall.combat.handle_world_combat_left_click(target)
	_expect(probe.abilities.back() == "rocket_launcher.primary", "装备采掘臂但选中火箭时，矿物不能劫持火箭输入")
	hall.hud.select_action("energy_cannon")
	current.vehicle.loadout = VehicleLoadout.new()
	before = probe.abilities.size()
	hall.combat.handle_world_combat_left_click(target)
	_expect(probe.abilities.size() == before, "卸下主装置后不沿用旧开炮或采矿逻辑")
	_test_assistant(hall, probe, current)
	await create_timer(0.2).timeout
	hall.free()
	for failure in failures:
		push_error(failure)
	print("COMBAT_CLICK_ROUTING checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 以真实场景和手动意图入口验证智脑动作、节流、工程臂排除和暂停边界。
## [param hall] 已提交野外地图的实际游戏入口。
## [param probe] 替代传输层的命令记录器。
## [param current] 当前人物聚合。
func _test_assistant(hall: Node2D, probe: IntentProbe, current: Player) -> void:
	probe.session = ClientMultiplayerSession.new()
	probe.add_child(probe.session)
	var panel := SmartAssistantPanel.new()
	hall.add_child(panel)
	panel.hide()
	var brain := SmartAssistantController.new()
	hall.add_child(brain)
	brain.set_process(false)
	brain.configure(hall.combat, panel)
	brain.policy.apply({"enabled": true, "auto_attack": true, "auto_pickup": true, "auto_repair": true})
	_equip(current, "glory_equipment_gun1000_c4c24e2500")
	var origin: Vector2 = hall.world_view.player.position
	var near := origin + Vector2(50, 0)
	var snapshot := {"local_vehicle": {"health": 20, "max_health": 100}, "ground_loot": [], "monsters": []}
	probe.combat_snapshot_received.emit(snapshot)
	var before := probe.abilities.size()
	brain._process(0.4)
	_expect(probe.abilities.size() == before + 1 and probe.abilities.back() == "self_repair", "低血智脑复用真实Z技能意图")
	brain._process(0.4)
	_expect(probe.abilities.size() == before + 1, "等待回包时维修请求节流")
	snapshot.local_vehicle.health = 80
	snapshot.ground_loot = [{"loot_id": "brain.near", "position": [near.x, near.y]}]
	probe.combat_snapshot_received.emit(snapshot)
	before = probe.pickups.size()
	brain._process(0.4)
	brain._process(0.4)
	_expect(probe.pickups.size() == before + 1 and probe.pickups.back() == "brain.near", "自动拾取复用真实拾取意图且不会重复刷请求")
	snapshot.ground_loot = []
	snapshot.monsters = [{"entity_id": "brain.target", "position": [near.x, near.y], "health": 100}]
	probe.combat_snapshot_received.emit(snapshot)
	var visual: WeaponAttackVisualController = hall.world_view.combat_attack_controllers.energy_cannon
	visual._process(5.0)
	before = probe.abilities.size()
	brain._process(0.4)
	_expect(probe.abilities.size() == before + 1 and probe.abilities.back() == "energy_cannon.primary", "自动攻击经过实际武器表现和网络意图入口")
	brain._process(0.4)
	_expect(probe.abilities.size() == before + 1, "自动攻击尊重武器冷却")
	visual._process(5.0)
	_equip(current, "glory_equipment_collector_ac947ee094")
	before = probe.abilities.size()
	brain._process(0.4)
	_expect(probe.abilities.size() == before, "采掘臂不被自动攻击当成能量炮")
	_equip(current, "glory_equipment_gun1000_c4c24e2500")
	probe.session._pending_vehicle_recovery = {"input_sequence": 1}
	brain._process(0.4)
	_expect(probe.abilities.size() == before and hall.combat.is_input_locked(), "回基地等待期间冻结自动及手动操作")
	probe.session._pending_vehicle_recovery.clear()
	brain._observed_at -= 4000
	brain._process(0.4)
	_expect(probe.abilities.size() == before, "过期快照不能驱动自动攻击")
	probe.map_joined.emit(&"next", "next.default", Vector2.ZERO, 1)
	brain._process(0.4)
	_expect(probe.abilities.size() == before and brain._snapshot.is_empty(), "切图立即丢弃旧目标")
	probe.combat_snapshot_received.emit(snapshot)
	brain.policy.enabled = false
	brain._process(0.4)
	_expect(probe.abilities.size() == before, "关闭智脑立即停止真实动作")
	_test_gun_missile_mode(hall, probe, current, brain)
	_test_smart_supplies(hall, probe, current, brain)


## 在实际战斗场景验证补给共用面板命令、失败节流及死亡和切图停用。
## [param hall] 真实场景。[param probe] 权威消息输入。[param current] 同一玩家投影。[param brain] 实际智脑控制器。
func _test_smart_supplies(hall: Node2D, probe: IntentProbe, current: Player, brain: SmartAssistantController) -> void:
	var sent: Array[Dictionary] = []
	hall.panel_session.command_dispatched.connect(func(command: Dictionary) -> void: sent.append(command.duplicate(true)))
	current.health = 100
	current.inventory = Inventory.new()
	var pack_id := catalog.definition_id_by_display_name("低级能量包")
	var food_id := catalog.definition_id_by_display_name("比萨")
	current.inventory.add_reward(catalog.create(pack_id, {"instance_id": "brain.pack", "quantity": 10}).value)
	current.inventory.add_reward(catalog.create(food_id, {"instance_id": "brain.food", "quantity": 3}).value)
	brain.policy.apply({"enabled": true, "auto_energy": true, "energy_definition_id": pack_id})
	var snapshot := {"vehicle_combat_active": true, "local_vehicle": {"health": 70, "max_health": 70,
		"reserve_energy": 100, "reserve_energy_capacity": 10000}, "ground_loot": [], "monsters": []}
	probe.combat_snapshot_received.emit(snapshot)
	brain._process(0.4)
	brain._process(0.4)
	_expect(sent.size() == 1 and sent[0].type == "use_inventory_item" and sent[0].instance_id == "brain.pack"
		and sent[0].inventory_revision == current.inventory.revision, "自动补包使用真实手动命令和当前库存版本，等待时不重发")
	_expect(current.inventory.find("brain.pack").quantity == 10, "客户端不预测消耗和补能")
	brain._retry_at.clear()
	snapshot.local_vehicle.reserve_energy = 10000
	probe.combat_snapshot_received.emit(snapshot)
	brain._process(0.4)
	_expect(sent.size() == 1, "满能量无补给请求")
	brain.policy.apply({"enabled": true, "auto_food": true, "food_definition_id": food_id})
	current.food_status = FoodStatus.new()
	var previous_kind: StringName = hall.world_view.player.presentation_kind
	hall.world_view.player.presentation_kind = PlayerWorldAvatar.CHARACTER_KIND
	brain._process(0.4)
	_expect(sent.size() == 2 and sent[1].instance_id == "brain.food", "城区制造期间也可使用食品，仍复用同一手动事务")
	hall.world_view.player.presentation_kind = previous_kind
	snapshot.local_vehicle.health = 0
	probe.combat_snapshot_received.emit(snapshot)
	_expect(not brain.policy.enabled and not brain._panel.toggles.enabled.button_pressed, "权威击毁立即停用并同步开关")
	snapshot.local_vehicle.health = 70
	probe.combat_snapshot_received.emit(snapshot)
	brain._process(0.4)
	_expect(sent.size() == 2 and not brain.policy.enabled, "后续恢复生命不自动启用")
	brain.policy.enabled = true
	probe.map_joined.emit(&"another", "another.default", Vector2.ZERO, 1)
	_expect(not brain.policy.enabled and brain._snapshot.is_empty(), "切图显式停用并清除旧目标")


## 验证原版半秒炮导切换、连续手动点击、自动攻击及暂停边界。
## [param hall] 已提交野外地图的实际场景。
## [param probe] 正式战斗入口的意图记录器。
## [param current] 当前已装配玩家。
## [param brain] 已配置且使用测试时钟的智脑。
func _test_gun_missile_mode(hall: Node2D, probe: IntentProbe, current: Player, brain: SmartAssistantController) -> void:
	_equip(current, "glory_equipment_gun1000_c4c24e2500")
	_expect(current.vehicle.loadout.restore(catalog.create("starter_missile", {"instance_id": "brain.missile"}).value).is_ok, "装备实际导弹")
	hall.hud.set_tactical_action("missile")
	hall.hud.select_action("energy_cannon")
	brain._settings_path = "res://.godot/gun-missile-%d.cfg" % Time.get_ticks_usec()
	brain._apply_settings({"enabled": true, "gun_missile_mode": true})
	var saved := ConfigFile.new()
	_expect(saved.load(brain._settings_path) == OK and saved.get_value("assistant", "preferences").gun_missile_mode,
		"炮导偏好实际写入角色配置")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(brain._settings_path))
	var origin: Vector2 = hall.world_view.player.position
	var target := origin + Vector2(100, 0)
	var snapshot := {"local_vehicle": {"health": 100, "max_health": 100}, "ground_loot": [], "monsters": [{
		"entity_id": "brain.locked", "species_id": "om_adult", "combat_actor_id": "om_adult_standard",
		"display_name": "炮导测试目标", "position": [target.x, target.y], "health": 60, "max_health": 60,
		"alive": true, "action": "idle", "facing_index": 0}]}
	hall.world_view.monster_world_controller.apply_snapshot(snapshot)
	probe.combat_snapshot_received.emit(snapshot)
	for visual: WeaponAttackVisualController in hall.world_view.combat_attack_controllers.values():
		visual._process(5.0)
	var before := probe.abilities.size()
	hall.combat.handle_world_combat_left_click(target)
	brain._process(0.49)
	_expect(hall.hud.selected_action() == "energy_cannon", "未到500毫秒不切换")
	brain._process(0.01)
	_expect(hall.hud.selected_action() == "missile" and probe.abilities.size() == before + 1,
		"自动攻击关闭时仍切到导弹，但不会自行开火")
	hall.combat.handle_world_combat_left_click(target)
	_expect(probe.abilities.slice(before) == ["energy_cannon.primary", "missile.primary"], "连续手动点击实际发出主炮和导弹两种意图")
	brain._process(0.5)
	_expect(hall.hud.selected_action() == "energy_cannon", "再过半秒切回主炮")
	brain._process(0.5)
	before = probe.abilities.size()
	hall.combat.handle_world_combat_left_click(target)
	_expect(probe.abilities.size() == before, "反复切换不重置导弹独立冷却")
	hall.world_view.combat_attack_controllers.missile._process(5.0)
	hall.combat.handle_world_combat_left_click(target + Vector2(500, 500))
	_expect(probe.abilities.size() == before, "导弹点击空地仍需锁定目标")
	brain.policy.auto_attack = true
	hall.world_view.combat_attack_controllers.energy_cannon._process(5.0)
	brain._process(0.5)
	brain._process(0.5)
	_expect(probe.abilities.slice(before) == ["energy_cannon.primary", "missile.primary"], "自动攻击复用相同的炮导选择")
	brain.policy.auto_attack = false
	for pause: String in ["disabled", "repair", "recovery", "stale", "destroyed"]:
		probe.combat_snapshot_received.emit(snapshot)
		brain.policy.enabled = pause != "disabled"
		brain._snapshot.local_vehicle.self_repair_active = pause == "repair"
		probe.session._pending_vehicle_recovery = {"input_sequence": 1} if pause == "recovery" else {}
		brain._observed_at -= 4000 if pause == "stale" else 0
		hall.combat.vehicle_destroyed = pause == "destroyed"
		var paused_selection: String = hall.hud.selected_action()
		brain._process(0.5)
		_expect(hall.hud.selected_action() == paused_selection, "暂停状态不切换：" + pause)
	hall.combat.vehicle_destroyed = false
	probe.session._pending_vehicle_recovery.clear()
	brain.policy.enabled = true
	probe.combat_snapshot_received.emit(snapshot)
	for equipment: String in ["glory_equipment_collector_ac947ee094", "glory_equipment_repair_aab7d81665"]:
		_equip(current, equipment)
		current.vehicle.loadout.restore(catalog.create("starter_missile", {"instance_id": "brain.missile"}).value)
		_expect(brain.policy.next_attack_weapon("energy_cannon", current.vehicle.loadout).is_empty(), "工程臂不参与炮导切换")
	_equip(current, "glory_equipment_gun1000_c4c24e2500")
	_expect(brain.policy.next_attack_weapon("energy_cannon", current.vehicle.loadout).is_empty(), "未装导弹不切换")
	current.vehicle.loadout.restore(catalog.create("starter_rocket_launcher", {"instance_id": "brain.rocket"}).value)
	_expect(brain.policy.next_attack_weapon("energy_cannon", current.vehicle.loadout).is_empty(), "火箭炮不冒充导弹")
	probe.map_joined.emit(&"next", "next.default", Vector2.ZERO, 1)
	var selected: String = hall.hud.selected_action()
	brain._process(0.5)
	_expect(hall.hud.selected_action() == selected and brain._weapon_elapsed == 0.0, "切图清空目标与切换时钟")


## 使用目录中的真实物品恢复底盘与指定主装置。
## [param player] 测试玩家聚合。
## [param equipment_id] 实际装备定义标识。
func _equip(player: Player, equipment_id: String) -> void:
	player.vehicle.loadout = VehicleLoadout.new()
	for id: String in ["glory_equipment_tank1000_27ae5e8059", equipment_id]:
		var created := catalog.create(id, {"instance_id": "click.%s" % id})
		_expect(created.is_ok and player.vehicle.loadout.restore(created.value).is_ok, "真实主装置装配成功")


## 汇总行为断言并在场景退出时统一报告。
## [param condition] 应满足的条件。
## [param message] 失败诊断。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
