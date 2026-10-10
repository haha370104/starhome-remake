extends SceneTree

class IntentProbe:
	extends HallMultiplayerPresenter
	var abilities: Array[String] = []
	var pickups: Array[String] = []

	## 捕获客户端发布的技能意图，不连接外部服务。
	func request_use_ability(ability_id: String, _position: Vector2) -> Dictionary:
		abilities.append(ability_id)
		return {"input_sequence": abilities.size()}

	## 捕获优先拾取的权威掉落标识。
	func request_loot_pickup(loot_id: String) -> Dictionary:
		pickups.append(loot_id)
		return {"loot_id": loot_id}


var checks := 0
var failures: Array[String] = []
var repairs: Array[Vector2] = []
var catalog := ItemCatalog.new()


## 延迟验证真实大厅中的手动战斗点击路由。
func _initialize() -> void:
	call_deferred("_run")


## 验证掉落优先级、名称拾取及实际主装置分发。
func _run() -> void:
	var hall: Node2D = load("res://scenes/main_hall.tscn").instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	await process_frame
	var active: ActiveWorldController = hall.active_world_controller
	var bundle := active.prepare_initial_bundle("res://data/maps/glory_nft_bl_d04.json")
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
	var view: GroundLootWorldView = loot.view_for_loot("overlap.loot")
	_expect(view != null and minerals.active_view_count() == 1, "真实掉落与矿物视图同时存在")
	if view == null:
		_finish(hall)
		return
	_equip(current, "glory_equipment_gun1000_c4c24e2500")
	var icon_point := view.to_global(view.local_hit_rect().get_center())
	_expect(not minerals.source_at(icon_point).is_empty(), "拾取测试点同时落在矿物范围内")
	var before := probe.pickups.size()
	hall.combat.handle_world_combat_left_click(icon_point)
	_expect(probe.pickups.size() == before + 1 and probe.pickups.back() == "overlap.loot",
		"掉落优先于矿物和武器点击")
	_expect(probe.abilities.is_empty() and repairs.is_empty(), "拾取不会同时发出开火、采矿或维修")

	loot.apply_snapshot({"ground_loot": [{"loot_id": "overlap.loot", "item_definition_id": "low_grade_biosilicon",
		"quantity": 2, "position": [1192, 1200]}]})
	view.set_hovered(true)
	await process_frame
	var tooltip := view.get_node("HoverTooltip") as Label
	var name_point := view.to_global(tooltip.position + Vector2(2.5, 13.5))
	_expect(not view.contains_world_point(name_point) and not minerals.source_at(name_point).is_empty(),
		"名称位于原图外且与矿物重叠")
	await _wait_for_loot_debounce(hall)
	before = probe.pickups.size()
	hall.combat.handle_world_combat_left_click(name_point)
	_expect(probe.pickups.size() == before + 1, "点击可见物品名优先拾取")
	_expect(tooltip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "名称不会吞掉世界拾取输入")
	view.set_hovered(false)
	_expect(loot.loot_at(name_point).is_empty(), "名称隐藏后不保留不可见拾取区域")
	loot.remove_loot("overlap.loot")
	await process_frame

	var target := Vector2(1200, 1200)
	_equip(current, "glory_equipment_gun1000_c4c24e2500")
	hall.hud.select_action("energy_cannon")
	hall.combat.handle_world_combat_left_click(target)
	_expect(probe.abilities == ["energy_cannon.primary"], "能量炮点击矿物仍使用真实开炮流程")
	_equip(current, "glory_equipment_repair_aab7d81665")
	hall.combat.handle_world_combat_left_click(target)
	_expect(repairs == [target] and probe.abilities.size() == 1, "维修臂点击矿物只产生维修意图")
	_expect(hall.hud.status_text().contains("维修") and not hall.hud.status_text().contains("采矿"),
		"维修反馈不误报采矿")
	_equip(current, "glory_equipment_collector_ac947ee094")
	hall.combat.handle_world_combat_left_click(target)
	_expect(probe.abilities.back() == "mining.collect" and probe.abilities.size() == 2,
		"采掘臂点击矿物才提交采矿")
	before = probe.abilities.size()
	hall.combat.handle_world_combat_left_click(Vector2(1600, 1600))
	_expect(probe.abilities.size() == before, "采掘臂点击空地不会发出开炮或采矿意图")
	hall.hud.set_tactical_action("rocket_launcher", 10)
	hall.hud.select_action("rocket_launcher")
	hall.combat.handle_world_combat_left_click(target)
	_expect(probe.abilities.back() == "rocket_launcher.primary",
		"装备采掘臂但选中火箭时，矿物不能劫持火箭输入")
	hall.hud.select_action("energy_cannon")
	current.vehicle.loadout = VehicleLoadout.new()
	before = probe.abilities.size()
	hall.combat.handle_world_combat_left_click(target)
	_expect(probe.abilities.size() == before, "卸下主装置后不沿用旧开炮或采矿逻辑")
	_finish(hall)


## 使用目录中的真实物品恢复战车本体与指定主装置。
func _equip(player: Player, equipment_id: String) -> void:
	player.vehicle.loadout = VehicleLoadout.new()
	for id: String in ["glory_equipment_tank1000_27ae5e8059", equipment_id]:
		var created := catalog.create(id, {"instance_id": "click.%s" % id})
		_expect(created.is_ok and player.vehicle.loadout.restore(created.value).is_ok, "真实主装置装配成功")


## 等待共享拾取节流真正结束，避免集成测试依赖渲染帧率。
func _wait_for_loot_debounce(hall: Node2D) -> void:
	while hall.combat._loot_pickup_debounce.remaining_msec(Time.get_ticks_msec()) > 0:
		await process_frame


## 释放大厅并汇总结果。
func _finish(hall: Node2D) -> void:
	hall.free()
	for failure in failures:
		push_error(failure)
	print("COMBAT_CLICK_ROUTING checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 汇总行为断言。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
