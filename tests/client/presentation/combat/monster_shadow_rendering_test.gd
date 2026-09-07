extends SceneTree

const MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"
const ACTORS := ["om_adult_standard", "om_larva_standard", "photosensitive_orb_standard", "toxic_gel_standard"]
var failures := PackedStringArray()


## 延迟创建真实怪物表现并检查所有方向和动作的阴影节点。
func _initialize() -> void:
	call_deferred("_run")


## 检查三类独立阴影与毒胶的原始空引用，并可生成原比例对照图。
func _run() -> void:
	root.size = Vector2i(1000, 540)
	var background := ColorRect.new()
	background.color = Color("85938c")
	background.size = Vector2(1000, 540)
	background.z_index = -100
	root.add_child(background)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var catalog := GloryMonsterPresentationCatalog.new()
	_expect(catalog.load_default(), "荣耀阴影引用应可读取")
	var preview_views: Array[MonsterWorldView] = []
	for actor_index: int in ACTORS.size():
		var actor_id: String = ACTORS[actor_index]
		var expects_shadow := actor_id != "toxic_gel_standard"
		var view := MonsterWorldView.new()
		root.add_child(view)
		_expect(view.configure(manifest, {
			"entity_id": actor_id, "combat_actor_id": actor_id,
			"display_name": manifest.actors[actor_id].display_name,
			"position": [120 + actor_index * 245, 145], "alive": true,
			"health": 60, "max_health": 100, "facing_index": 0, "action": "idle",
		}) == OK, "%s 应能创建" % actor_id)
		view.set_process(false)
		view.set_hovered(true)
		preview_views.append(view)
		var shadow := view.presenter.get_node_or_null("Shadow") as AnimatedSprite2D
		var body := view.presenter.get_node("Body") as AnimatedSprite2D
		_expect((shadow != null) == expects_shadow, "%s 阴影层应符合原始配置" % actor_id)
		var shadow_refs: Dictionary = catalog.definition_for_actor(actor_id).get("shadow_actions", {})
		for action: String in ["idle", "move", "attack"]:
			_expect(not String(shadow_refs.get(action, "")).is_empty() == expects_shadow,
				"%s %s 源表阴影引用应与运行时一致" % [actor_id, action])
			view.presenter.set_action(StringName(action))
			for direction: int in 8:
				view.presenter.set_direction(direction)
				view.presenter.advance(0.1)
				if shadow != null:
					_expect(shadow.visible and shadow.sprite_frames != null \
						and shadow.z_index < body.z_index and shadow.z_index > background.z_index,
						"%s %s 方向 %d 阴影应显示在地面之上、身体之下" % [actor_id, action, direction])
		view.presenter.set_action(&"idle")
		view.presenter.set_direction(0)
		if shadow != null:
			# 下排只展示同一原始阴影，便于区分“没有阴影”和“阴影被身体遮住”。
			var isolated := Sprite2D.new()
			isolated.centered = false
			isolated.texture = shadow.sprite_frames.get_frame_texture(shadow.animation, shadow.frame)
			isolated.position = view.position + shadow.position + Vector2(0, 220)
			root.add_child(isolated)
			if actor_id == "om_larva_standard":
				var pixels := isolated.texture.get_image()
				var maximum_alpha := 0.0
				for y: int in pixels.get_height():
					for x: int in pixels.get_width():
						maximum_alpha = maxf(maximum_alpha, pixels.get_pixel(x, y).a)
				_expect(maximum_alpha > 0.0 and maximum_alpha < 0.4,
					"幼虫阴影应有实际半透明像素，不是空贴图")
	await process_frame
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/monster_shadows.png")
	for view: MonsterWorldView in preview_views:
		view.free()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("MONSTER_SHADOW_RENDERING_OK")
	quit(0 if failures.is_empty() else 1)


## 记录渲染契约断言。
## [param condition] 必须成立的条件。
## [param message] 失败原因。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
