extends SceneTree

var failures: PackedStringArray = []
var checks := 0


## 延迟构建实际客户端场景，所有状态仅存在测试内存中。
func _initialize() -> void:
	call_deferred("_run")


## 验证商店全系列武器、采掘臂换回虎式、HUD、副武器面板和窗口遮挡。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var hall: Node2D = load("res://scenes/main_hall.tscn").instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	var field: Dictionary = hall.active_world_controller.prepare_initial_bundle("res://data/maps/d04_field_zone.json")
	_expect(hall.active_world_controller.commit_bundle(field, field.definition.spawn_for_entry(1).position), "真实野外地图可提交")
	var catalog := ItemCatalog.new()
	_expect(catalog.initialize().is_ok, "物品目录可用")
	var player := Player.new({"character_id": "test.weapons", "display_name": "装备测试", "skills": {"energy_cannon": 1000},
		"vehicle": {"max_health": 70, "health": 70, "working_energy": 100, "working_energy_capacity": 100}})
	_install(player, catalog, "recruit_tank", 0)
	_install(player, catalog, "beginner_engine", 3)
	var primary: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/commerce/weapon_merchant_v1.json").value.merchant.official_whitelist_ids
	var bindings: Dictionary = JsonConfigLoader.load_dictionary("res://data/presentation/weapon_visual_bindings_v1.json").value.weapons
	var controller: WeaponAttackVisualController = hall.world_view.combat_attack_controllers["energy_cannon"]
	for id: String in primary.energy_cannon:
		_install(player, catalog, id, 1)
		hall.player_binding.on_current_player_changed(player)
		_expect(hall.world_view.player.combat_presenter.layer_frame(&"primary_weapon") >= 0, "所有在售主炮具备可绘制的世界模型：" + id)
		var actual_id := player.vehicle.loadout.at(1).definition_id
		_expect(controller._visual_definition_id == StringName(actual_id) and not controller._weapon.is_empty(), "弹体选择跟随实际主炮")
		if bindings.has(actual_id):
			_expect(controller._projectile_frames == CombatAnimationLibrary.load_ale(bindings[actual_id].projectile.ale_reference), "弹体使用原版最终风格映射：" + id)
	_install(player, catalog, "glory_equipment_collector_ac947ee094", 1)
	hall.player_binding.on_current_player_changed(player)
	_expect(controller._weapon.is_empty(), "采掘臂清除后续开炮配置")
	_install(player, catalog, "glory_equipment_gun9_d2426d05e9", 1)
	hall.player_binding.on_current_player_changed(player)
	var primary_layer: Dictionary = hall.world_view.player.combat_presenter._layer_configs[&"primary_weapon"]
	_expect(primary_layer.actions.idle.ale_reference == "../pic3/equip/body/gun8.ale", "采掘臂切回虎式突袭后使用虎式炮身")
	_expect(controller._weapon.projectile.ale_reference == "pic3/bullet/bullet8", "虎式默认风格覆盖 bullet9 声明为 bullet8")
	controller.request_fire(Vector2.ZERO, Vector2(220, 0))
	var fired_frames: SpriteFrames = controller._projectiles[0].node.get_node("Sprite").sprite_frames
	controller.select_weapon(&"recruit_energy_cannon")
	_expect(controller._projectiles[0].node.get_node("Sprite").sprite_frames == fired_frames, "换装不会改变在途弹体")
	controller.advance(2.0)
	_expect(controller.active_projectile_count() == 0, "换装前的弹体仍能正常结束")
	controller.clear_effects()
	_test_energy_confirmation(hall, player)
	var secondary: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/commerce/special_weapon_merchant_v1.json").value.merchant.official_whitelist_ids
	var projector := PlayerPanelProjector.new(catalog)
	var surface := CanvasLayer.new()
	surface.layer = 60
	root.add_child(surface)
	var panel := VehicleEquipmentPanel.new()
	surface.add_child(panel)
	for kind: String in ["missile_weapon", "rocket_weapon"]:
		for id: String in secondary[kind]:
			_install(player, catalog, id, 13)
			hall.player_binding.on_current_player_changed(player)
			var equipment := player.vehicle.loadout.at(13) as VehicleWeapon
			var mode := equipment.combat_mode()
			_expect(hall.hud.state.tactical_action_id == mode, "任意等级副武器均显示对应HUD按钮：" + id)
			var primary_sprite: AnimatedSprite2D = hall.world_view.player.combat_presenter._layers[&"primary_weapon"]
			var primary_frames := primary_sprite.sprite_frames
			var primary_frame := primary_sprite.frame
			var primary_offset := primary_sprite.offset
			hall.hud.select_action(mode)
			_expect(hall.hud.selected_action() == mode, "副武器HUD可以实际选中")
			_expect(primary_sprite.visible and primary_sprite.sprite_frames == primary_frames and primary_sprite.frame == primary_frame and primary_sprite.offset == primary_offset,
				"切换副武器不能隐藏、移动或替换战车主炮")
			hall.hud.select_action("energy_cannon")
			_expect(primary_sprite.visible and primary_sprite.sprite_frames == primary_frames and primary_sprite.frame == primary_frame, "切回主武器保持同一炮身")
			hall.hud.select_action(mode)
			var visual: WeaponAttackVisualController = hall.world_view.combat_attack_controllers[mode]
			_expect(not visual._weapon.is_empty(), "副武器弹效已配置：" + id)
			panel.apply_snapshot({"equipped": [projector._equipment_view(equipment, "vehicle")]})
			await process_frame
			var icon := panel._slot_root.get_node_or_null("Location_13_" + equipment.definition_id) as TextureRect
			_expect(icon != null and icon.texture != null and icon.position == Vector2(96, 58), "副武器必须绘制在可见槽位：" + id)
			var layer_id := &"missile_weapon" if mode == "missile" else &"rocket_weapon"
			_expect(not hall.world_view.player.combat_presenter._layers.has(layer_id), "副武器只在装置1槽位显示，不叠加到车身")
			hall.combat.on_combat_event_received({"event_type": mode + "_projectile_spawned", "skill_id": mode,
				"attacker_id": String(hall.multiplayer_presenter.session.local_entity_id), "weapon_id": id,
				"shot_id": "test.secondary." + id, "input_sequence": 10,
				"actor_position": [200, 200], "endpoint": [500, 200], "direction": [1, 0]})
			_expect(visual.active_projectile_count() == 1 and primary_sprite.visible and primary_sprite.sprite_frames == primary_frames and primary_sprite.frame == primary_frame,
				"副武器确认开火只产生弹体，主炮保持显示")
			visual.clear_effects()
	panel.apply_snapshot(projector.build_bundle(player).vehicle)
	panel.position = Vector2(24, 24)
	panel.show()
	var cover := DraggableGameWindow.new()
	surface.add_child(cover)
	var solid := Image.create(350, 420, false, Image.FORMAT_RGBA8)
	solid.fill(Color("102a44"))
	cover.configure(Vector2(350, 420), ImageTexture.create_from_image(solid), Vector2(325, 8))
	cover.position = Vector2(120, 54)
	cover.move_to_front()
	if "--capture-equipment" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		var captured := root.get_texture().get_image()
		_expect(captured.get_pixel(220, 280).is_equal_approx(Color("102a44")), "置顶窗口的实际像素不能被后方战车穿透")
		captured.save_png("res://.godot/equipment_window_stacking.png")
		cover.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/equipment_weapon_preview.png")
	cover.free()
	panel.free()
	surface.free()
	await create_timer(0.2).timeout
	hall.free()
	for failure in failures:
		push_error(failure)
	print("EQUIPPED_WEAPON_PRESENTATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 把真实权威开火结果接回客户端，验证拒绝不播放、扣能蓝条和重复快照去重。
## [param hall] 已进入野外的隔离客户端场景。
## [param player] 已装备虎式突袭的内存玩家。
func _test_energy_confirmation(hall: Node2D, player: Player) -> void:
	var catalog: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var loadout := catalog.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500.0, "base_speed_cap": 240.0})
	_expect(loadout.is_ok, "当前装备可构造真实权威装配")
	var server := AuthoritativeCombatModule.new()
	server.configure(20, 17, 0.0)
	var actor_id := String(hall.multiplayer_presenter.session.local_entity_id)
	_expect(not actor_id.is_empty(), "客户端会话已有本地玩家身份")
	var registered := server.register_vehicle(actor_id, "equipment.test", Vector2(200, 200), loadout.value.assembly, loadout.value.weapons)
	_expect(registered.is_ok, "测试战车可登记权威战斗状态")
	var state: VehicleCombatState = registered.value
	var controller: WeaponAttackVisualController = hall.world_view.combat_attack_controllers["energy_cannon"]
	state.working_energy = 20.0
	var rejected := server.handle_weapon_attack(actor_id, UseAbilityIntent.new("equipment.test", "energy_cannon.primary", Vector2(500, 200), 1).to_dictionary())
	_expect(not rejected.is_ok and rejected.error_code == &"combat.insufficient_working_energy", "虎式开炮真实拒绝能量不足")
	hall.combat.on_combat_snapshot_received(server.snapshot_for_actor(actor_id))
	_expect(server.pending_projectiles.is_empty() and controller.active_projectile_count() == 0, "拒绝开火不产生权威或客户端弹体")
	_expect(is_equal_approx(hall.world_view.player.combat_status_bar._energy_ratio, 0.2), "真实权威快照将蓝条显示为20%")
	state.working_energy = state.working_energy_capacity
	var accepted := server.handle_weapon_attack(actor_id, UseAbilityIntent.new("equipment.test", "energy_cannon.primary", Vector2(500, 200), 2).to_dictionary())
	_expect(accepted.is_ok, "足够工作能量时允许虎式开火")
	if accepted.is_ok:
		hall.combat.on_combat_event_received(accepted.value)
		hall.combat.on_combat_snapshot_received(server.snapshot_for_actor(actor_id))
		_expect(controller.active_projectile_count() == 1, "开火事件和重复快照合计只播放一次")
		_expect(is_equal_approx(hall.world_view.player.combat_status_bar._energy_ratio, 0.5), "虎式每炮扣50能量并投影为半条")
		_expect(controller._weapon.projectile.ale_reference == "pic3/bullet/bullet8", "真实开火事件仍使用虎式专属弹体")
	controller.clear_effects()


## 用目录物品替换内存玩家的指定槽位，跳过商城但保留真实装配规则。
## [param player] 仅用于本测试的聚合。
## [param catalog] 统一物品目录。
## [param id] 待装配物品定义。
## [param location] 固定逻辑槽位。
func _install(player: Player, catalog: ItemCatalog, id: String, location: int) -> void:
	var created := catalog.create(id, {"instance_id": "test." + id})
	_expect(created.is_ok, "目录可以创建装备：" + id)
	_expect(player.vehicle.loadout.equip(created.value, location, player.vehicle.loadout.revision).is_ok, "装备可以替换槽位")


## 累计断言，不因单个装备错误跳过后续同系列回归。
## [param condition] 被验证的业务条件。
## [param message] 失败时的诊断文字。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
