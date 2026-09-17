extends SceneTree

var checks := 0
var failures: Array[String] = []
var event_id := 0


## 在节点树就绪后运行真实怪物事件路由和命中资源回归。
func _initialize() -> void:
	call_deferred("_run")


## 验证远程命中、移动目标、去重、落空和迟到事件的完整表现链路。
func _run() -> void:
	root.size = Vector2i(640, 360)
	var manifest: Dictionary = JsonConfigLoader.load_dictionary("res://assets/equipment_world/combat_visual_manifest.json").value
	var world := Node2D.new()
	root.add_child(world)
	var player := CombatVisualPresenter.new()
	world.add_child(player)
	_expect(player.configure(manifest) == OK and player.present_actor(&"starter_combat_vehicle") == OK, "真实战车外观须可加载")
	player.position = Vector2(320, 200)
	var controller := MonsterWorldController.new()
	root.add_child(controller)
	_expect(controller.configure(world, manifest, player) == OK, "实际怪物表现控制器须可配置")
	controller.set_process(false)
	var effects: MonsterAttackEffectController = controller._attack_effects
	effects.set_process(false)
	var catalog := JsonConfigLoader.load_dictionary("res://data/gameplay/glory/monster_hit_effects_v1.json")
	var source_rows: Array = JsonConfigLoader.load_dictionary(GloryMonsterPresentationCatalog.DEFAULT_PATH).value.definitions
	var archetypes: Dictionary = {}
	var projectiles: Dictionary = {}
	var covered: Dictionary = {}
	for row: Dictionary in source_rows:
		archetypes[row.combat_actor_id] = row.combat.attack_archetype
		projectiles[row.combat_actor_id] = row.presentation.projectile
	for effect: Dictionary in catalog.value.definitions:
		for actor: String in effect.combat_actor_ids:
			_expect(not covered.has(actor), "命中配置中的怪物身份不得重复")
			covered[actor] = true
			var attack := _event("monster_attack_started", actor + ".hit", actor)
			attack.attack_archetype = archetypes[actor]
			# 接触型怪物仍沿同一结算入口；此处主要验证远程普通炮弹的完整路由。
			_dispatch(controller, attack)
			var expected_projectiles := 0 if archetypes[actor] == "contact_melee" or projectiles[actor].is_empty() else 1
			_expect(effects.active_projectile_count() == expected_projectiles, "%s 须按实际攻击类型创建弹体" % actor)
			player.position += Vector2(10, 0)
			var resolved := _event("monster_attack_resolved", actor + ".hit", actor)
			resolved.attack_archetype = archetypes[actor]
			_dispatch(controller, resolved)
			_expect(effects.active_projectile_count() == 0, "命中后须按编号立即清除在途弹体")
			_expect(effects.active_impact_count() == 1, "%s 远程命中须创建原图动画" % actor)
			if effects.active_impact_count() == 1:
				var state: Dictionary = effects._active_impacts[0]
				var impact: Node2D = state.node
				_expect(impact.position == player.position and impact.z_index > player.z_index,
					"命中显示在当前可见战车上方，不使用网络旧脚点")
				_expect(is_equal_approx(float(state.fps), 1000.0 / 66.0), "原版 laserblast 按66毫秒逐帧播放")
				var fixed_position := impact.position
				player.position.x += 15
				effects.advance(0.067)
				_expect(impact.position == fixed_position, "爆炸是世界瞬时效果，创建后不绑定车身")
				var sprite := impact.get_node("Sprite")
				if sprite is AnimatedSprite2D:
					_expect(sprite.frame == 1, "导入帧动画须实际前进")
				else:
					_expect(sprite.texture == state.ale_frames[1].texture, "ALE帧动画须实际前进")
				if actor == "glory_npc_015" and "--capture" in OS.get_cmdline_user_args():
					player.position = fixed_position
					await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("res://.godot/shell-om-hit-runtime.png")
			_dispatch(controller, resolved)
			_expect(effects.active_impact_count() == 1, "快照重放不得重复爆炸")
			effects.advance(2.0)
			_expect(effects.active_impact_count() == 0, "一次播放结束须清除节点")
			player.position = Vector2(320, 200)
	for pending: Dictionary in catalog.value.get("unresolved", []):
		_expect(not covered.has(pending.combat_actor_id), "待核实怪物不得同时配置已确认效果")
		covered[pending.combat_actor_id] = true
		_dispatch(controller, _event("monster_attack_resolved", pending.combat_actor_id + ".pending", pending.combat_actor_id))
		_expect(effects.active_impact_count() == 0, "%s 不得把旧表中的怪物身体动画放到战车上" % pending.display_name)
	for row: Dictionary in source_rows:
		if row.combat.attack_archetype == "corrosive_projectile":
			var corrosion_event := _event("monster_attack_resolved", row.combat_actor_id + ".corrosion", row.combat_actor_id)
			corrosion_event.attack_archetype = "corrosive_projectile"
			_dispatch(controller, corrosion_event)
			_expect(effects.active_impact_count() == 0, "%s 保持独立腐蚀效果" % row.display_name)
		else:
			_expect(covered.has(row.combat_actor_id), "%s 必须配置效果或记录待核实原因，不能静默漏项" % row.display_name)
	var actor := "om_larva_standard"
	_dispatch(controller, _event("monster_attack_started", "dodged", actor))
	_dispatch(controller, _event("monster_attack_expired", "dodged", actor))
	_expect(effects.active_projectile_count() == 0 and effects.active_impact_count() == 0, "躲开的炮弹只清理，不假播受击爆炸")
	_dispatch(controller, _event("monster_attack_resolved", "late", actor))
	_dispatch(controller, _event("monster_attack_started", "late", actor))
	_expect(effects.active_projectile_count() == 0 and effects.active_impact_count() == 1, "晚到开始不能复活已结算弹体")
	var poison := _event("monster_attack_resolved", "poison", "toxic_gel_standard")
	poison.attack_archetype = "corrosive_projectile"
	_dispatch(controller, poison)
	_expect(effects.active_impact_count() == 1, "毒胶沿独立腐蚀流程，不误套普通爆炸")
	var unknown := _event("monster_attack_resolved", "unknown", "missing_actor")
	_dispatch(controller, unknown)
	_expect(effects.active_impact_count() == 1, "未知怪物不回退成感光质特效")
	controller.clear()
	_expect(effects.active_projectile_count() == 0 and effects.active_impact_count() == 0, "切图须清理全部瞬态效果")
	controller.free()
	world.free()
	for failure: String in failures:
		push_error(failure)
	print("MONSTER_HIT_PRESENTATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 构造与权威怪物开始、命中、落空事件相同的必要字段。
## [param kind] 事件类型。
## [param attack_id] 用于弹体与命中对账的稳定编号。
## [param actor] 原版怪物外观身份。
## 返回事件载荷；默认零伤害仍应表现真实碰撞。
func _event(kind: String, attack_id: String, actor: String) -> Dictionary:
	event_id += 1
	return {"event_id": event_id, "event_type": kind, "attack_id": attack_id,
		"attack_archetype": "ranged_projectile", "combat_actor_id": actor,
		"origin": [100, 184], "target_position": [320, 184], "projectile_speed": 100,
		"target_entity_id": "player.local", "impact_position": [290, 184], "damage": 0}


## 从真实世界控制器的快照入口消费事件。
## [param controller] 怪物表现总入口。
## [param event] 待消费的事件。
func _dispatch(controller: MonsterWorldController, event: Dictionary) -> void:
	controller.apply_snapshot({"local_entity_id": "player.local", "monsters": [], "recent_events": [event]})


## 收集断言及其失败诊断。
## [param condition] 必须成立的条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
