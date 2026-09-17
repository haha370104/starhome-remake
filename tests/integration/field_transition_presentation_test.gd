extends SceneTree

const FIELD_MAPS := ["buli_c03_field_zone", "buli_c04_field_zone", "buli_c05_field_zone",
	"buli_d03_field_zone", "buli_d05_field_zone"]
var failures: Array[String] = []
var checks := 0
var audited_maps := 0
var audited_markers := 0


## 审计全部已发布野外表现，再用真实场景验证曾重复烘焙箭头的五张地图。
func _initialize() -> void:
	call_deferred("_run")


## 加载发布目录并提交真实地图，可选输出C04传送点的两个动画帧和战车遮挡图。
func _run() -> void:
	_expect(bool(RuntimeContentBootstrap.mount_default().get("ok", false)), "内容包须可挂载")
	_audit_field_maps()
	root.size = Vector2i(640, 360)
	var hall: Node2D = load("res://scenes/main_hall.tscn").instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	for map_id: String in FIELD_MAPS:
		var active: ActiveWorldController = hall.active_world_controller
		var bundle := active.prepare_initial_bundle("res://data/maps/%s.json" % map_id)
		_expect(not bundle.is_empty(), "%s 地图依赖须可加载" % map_id)
		if bundle.is_empty():
			continue
		_expect(active.commit_bundle(bundle, bundle.definition.spawn_for_entry(0).position), "%s 地图须可提交" % map_id)
		_expect(active.transition_views.size() == active.definition.enabled_transitions().size(),
			"%s 每个有效出口须有唯一动画视图" % map_id)
		for view: MapTransitionView in active.transition_views:
			var icon := view.get_node("AnimatedIcon") as AnimatedSprite2D
			var frame_before := icon.frame
			var progress_before := icon.frame_progress
			await create_timer(0.12).timeout
			_expect(icon.is_playing() and (icon.frame != frame_before or icon.frame_progress != progress_before),
				"%s 的 %s 必须实际推进动画" % [map_id, view.transition_id])
			_expect(view.z_index < hall.world_view.player.z_index, "传送箭头须位于战车下方")
		if map_id == "buli_c04_field_zone" and "--capture" in OS.get_cmdline_user_args():
			await _capture_c04(hall)
		await process_frame
	hall.free()
	for failure: String in failures:
		push_error(failure)
	print("FIELD_TRANSITION_PRESENTATION maps=%d markers=%d checks=%d failures=%d" % [
		audited_maps, audited_markers, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 遍历基础与内容包地图，拒绝未排除静态传送贴图的旧发布产物。
func _audit_field_maps() -> void:
	var paths: Dictionary = {}
	var index := JsonConfigLoader.load_dictionary("res://data/content/glory_map_runtime_index_v1.json")
	for row: Dictionary in index.value.runtime_maps:
		paths[String(row.definition_path)] = true
	for filename: String in DirAccess.get_files_at("res://data/maps"):
		if filename.ends_with(".json"):
			paths["res://data/maps/" + filename] = true
	var markers := MapTransitionMarkerCatalog.new()
	_expect(markers.load_default() == OK, "八方向目录须有效")
	for path: String in paths:
		var raw := JsonConfigLoader.load_dictionary(path)
		if not raw.is_ok or raw.value.get("category", "") != "field":
			continue
		var definition := MapDefinitionLoader.new().load_file(path)
		_expect(definition != null, "%s 野外定义须有效" % path)
		if definition == null or definition.enabled_transitions().is_empty():
			continue
		if String(definition.resource_paths.scene_manifest).is_empty() and raw.value.get(
			"source_audit", {}).get("presentation_state", "") == "blocked_by_missing_business_asset_import":
			continue
		audited_maps += 1
		var manifest := JsonConfigLoader.load_dictionary(String(definition.resource_paths.scene_manifest))
		_expect(manifest.is_ok, "%s 场景清单须可读取" % definition.map_id)
		if not manifest.is_ok:
			continue
		var validation: Dictionary = manifest.value.get("composition", {}).get("validation", {})
		_expect(bool(validation.get("runtime_transition_registry_only", false)),
			"%s 仍为未剔除静态传送箭头的旧产物" % definition.map_id)
		# 原始解包就缺失的箭头未进入 composite，不能当成遗留静态贴图。
		var unresolved := int(validation.get("unresolved_static_transition_sources", 0))
		_expect(unresolved >= 0 and unresolved <= int(validation.get("excluded_static_transition_placements", 0)),
			"%s 缺失源记录须属于已排除的传送点放置" % definition.map_id)
		for transition: MapTransition in definition.enabled_transitions():
			var view := MapTransitionView.new()
			var presentation := markers.resolve(StringName(transition.presentation.get("orientation", "")), transition.source_anchor)
			_expect(view.configure(transition, presentation) == OK, "%s 出口须使用公共动画" % definition.map_id)
			if view.get_child_count() > 0:
				var icon := view.get_node("AnimatedIcon") as AnimatedSprite2D
				_expect(icon.sprite_frames.get_frame_count(icon.animation) > 1
					and icon.sprite_frames.get_animation_loop(icon.animation) and view.z_index < 0,
					"出口必须使用多帧循环动画并位于实体下方")
			view.free()
			audited_markers += 1
	_expect(audited_maps > FIELD_MAPS.size(), "审计须覆盖内容包野外，不能仅检查手工地图")


## 输出同一出口两帧动画与战车覆盖情况，用于实际像素检查。
## [param hall] 已提交C04的真实主场景。
func _capture_c04(hall: Node2D) -> void:
	hall.hud.hide()
	var marker: MapTransitionView = hall.active_world_controller.transition_view_by_id(&"exit_to_c05")
	var icon := marker.get_node("AnimatedIcon") as AnimatedSprite2D
	var camera: Camera2D = hall.world_view.camera
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2(2, 2)
	camera.position = marker.position + Vector2(28, 22)
	hall.set_process(false)
	hall.world_view.player.hide()
	icon.pause()
	for frame in [0, 5]:
		icon.frame = frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/c04-portal-frame-%d.png" % frame)
	hall.world_view.player.show()
	hall.local_player_controller.set_position(marker.position + Vector2(28, 35))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/c04-portal-vehicle.png")
	icon.play()
	hall.hud.show()
	hall.set_process(true)


## 记录测试断言和失败说明。
## [param condition] 应成立的条件。
## [param message] 失败诊断。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
