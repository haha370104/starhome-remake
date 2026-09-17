extends SceneTree

const DecorationScript := preload("res://scripts/client/world/recovered_scene_decoration.gd")
var failures: PackedStringArray = []
var checks := 0


## 延迟启动真实客户端表现回归，禁止连接服务端或改动玩家存档。
func _initialize() -> void:
	CombatTraceLogger.configure(false)
	call_deferred("_run")


## 检查实际物品解析、六个弹体、交易中心动画、切图清理及失败提交隔离。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var hall: Node2D = load("res://scenes/main_hall.tscn").instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	var catalog := ItemCatalog.new()
	_expect(catalog.initialize().is_ok, "目录应能加载全部恢复覆盖项")
	var overrides: Dictionary = JsonConfigLoader.load_dictionary("res://data/presentation/recovered_equipment_v1.json").value.definitions
	for id: String in overrides:
		var created := catalog.create(id, {"instance_id": "test.recovery." + id})
		_expect(created.is_ok, "恢复项应能实例化：" + id)
		for mode: String in overrides[id]:
			var presentation: Dictionary = created.value.presentation_for(mode)
			var resolved := ItemPresentationTextureResolver.resolve(presentation)
			_expect(not resolved.is_empty() and resolved.get("texture") != null, "实际展示适配器应解析恢复项：" + id + "/" + mode)
	var stone_id := catalog.definition_id_by_display_name("加工石")
	var stone := catalog.create(stone_id, {"instance_id": "test.stone"})
	var stone_icon := ItemPresentationTextureResolver.resolve(stone.value.presentation_for("inventory"))
	_expect(stone_icon.get("logical_id") == "pic2/stuff/processstone", "加工石应使用找回原图")
	var bindings: Dictionary = JsonConfigLoader.load_dictionary("res://data/presentation/weapon_visual_bindings_v1.json").value.weapons
	var recovered_weapons := 0
	for id: String in bindings:
		var binding: Dictionary = bindings[id]
		if not binding.projectile.has("source_release"):
			continue
		recovered_weapons += 1
		var controller: WeaponAttackVisualController = hall.world_view.combat_attack_controllers[binding.mode]
		_expect(controller.select_weapon(StringName(id)) == OK, "武器应选择找回的弹体：" + id)
		controller.request_fire(Vector2.ZERO, Vector2(180, 0))
		_expect(controller.active_projectile_count() == 1, "恢复武器可生成在途弹体：" + id)
		if controller.active_projectile_count() == 1:
			var sprite: AnimatedSprite2D = controller._projectiles[0].node.get_node("Sprite")
			_expect(sprite.sprite_frames == CombatAnimationLibrary.load_ale(binding.projectile.ale_reference), "实际发射弹体应使用该武器的恢复图")
		controller.advance(10.0)
		controller.clear_effects()
	_expect(recovered_weapons == 6, "应补齐六个武器绑定")
	var definition: MapDefinition = MapDefinitionLoader.new().load_file("res://content/glory/map_definitions/glory_nft_bl_traderoom1.json")
	var bundle := {"definition": definition,
		"map_manifest": JSON.parse_string(FileAccess.get_file_as_string(definition.resource_paths.scene_manifest)),
		"resources": {"floor": RuntimeTextureLoader.load_texture(definition.resource_paths.floor), "minimap": RuntimeTextureLoader.load_texture(definition.resource_paths.minimap)}}
	_expect(hall.active_world_controller.commit_bundle(bundle, definition.spawn_for_entry(1).position), "实际交易中心应能原子提交")
	var recovered: Array[Node2D] = []
	for node: Node2D in hall.active_world_controller.scene_nodes:
		if node.get_script() == DecorationScript:
			recovered.append(node)
	_expect(recovered.size() == 3, "交易中心必须实际显示三个缺失屏幕")
	var expected_anchors := [Vector2(1053, 206), Vector2(1478, 415), Vector2(2179, 766)]
	for i in recovered.size():
		var node: Node2D = recovered[i]
		node.set_process(false)
		_expect(node.position == expected_anchors[i], "屏幕遵循原版位置")
		for frame in 12:
			node._elapsed = float(frame) / 10.0 + 0.0001
			node._process(0.0)
			_expect(node.get_node("Animation").texture == node._textures[frame], "循环必须覆盖全部12帧")
			_expect(node.get_node("Animation").position == node._origins[frame], "每帧应用对应原点")
	if OS.get_cmdline_user_args().has("--capture") and not recovered.is_empty():
		hall.local_player_controller.set_process(false)
		hall.local_player_controller.set_physics_process(false)
		hall.world_view.camera.position_smoothing_enabled = false
		hall.world_view.camera.position = recovered[0].position
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/recovered_trade_center.png")
	var invalid := bundle.duplicate()
	invalid["resources"] = {}
	_expect(not hall.active_world_controller.commit_bundle(invalid, Vector2.ZERO), "无效提交应保留旧地图")
	_expect(recovered.size() == 3 and is_instance_valid(recovered[0]), "提交失败不得清理已显示动画")
	var previous_ids: Array[int] = []
	for node: Node2D in recovered:
		previous_ids.append(node.get_instance_id())
	var field: Dictionary = hall.active_world_controller.prepare_initial_bundle("res://data/maps/d04_field_zone.json")
	_expect(hall.active_world_controller.commit_bundle(field, field.definition.spawn_for_entry(1).position), "离开交易中心应成功")
	await process_frame
	await process_frame
	for id in previous_ids:
		_expect(not is_instance_id_valid(id), "切图应释放恢复动画")
	hall.queue_free()
	await process_frame
	if failures.is_empty():
		print("RECOVERED_ASSETS_RUNTIME_OK (%d assertions)" % checks)
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计恢复内容的实际表现断言。
## [param condition] 已执行的表现行为是否符合预期。
## [param message] 失败时的具体用途与诊断信息。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
