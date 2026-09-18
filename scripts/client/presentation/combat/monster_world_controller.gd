class_name MonsterWorldController
extends Node

const MonsterWorldViewScript := preload("res://scripts/client/presentation/combat/monster_world_view.gd")
const CombatDamageFloatScript := preload("res://scripts/client/presentation/combat/combat_damage_float.gd")
const MonsterDeathEffectControllerScript := preload(
	"res://scripts/client/presentation/combat/monster_death_effect_controller.gd"
)
const MonsterAttackEffectControllerScript := preload(
	"res://scripts/client/presentation/combat/monster_attack_effect_controller.gd"
)
const RuntimeContentBootstrapScript := preload("res://scripts/content/runtime_content_bootstrap.gd")
const AleSpriteRepositoryScript := preload("res://scripts/content/ale_sprite_repository.gd")
const GloryMonsterPresentationCatalogScript := preload(
	"res://scripts/content/glory_monster_presentation_catalog.gd"
)

var _world_parent: Node2D
var _manifest: Dictionary = {}
var _views: Dictionary = {}
var _local_player: Node2D
var _last_event_id := 0
var _death_effects: MonsterDeathEffectController
var _attack_effects: MonsterAttackEffectController
var _sama_effects: SamaEffectController
var _hovered_entity_id := ""
var _ale_repository: RefCounted
var _glory_presentations: RefCounted


## 执行 `configure` 对应的模块操作。
## [param world_parent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param manifest] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param local_player] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func configure(world_parent: Node2D, manifest: Dictionary, local_player: Node2D) -> Error:
	if world_parent == null or manifest.is_empty() or local_player == null:
		return ERR_INVALID_PARAMETER
	_world_parent = world_parent
	_manifest = manifest.duplicate(true)
	_local_player = local_player
	var mount_result := RuntimeContentBootstrapScript.mount_default()
	if bool(mount_result.get("ok", false)):
		_ale_repository = AleSpriteRepositoryScript.new()
		if not _ale_repository.load_default():
			_ale_repository = null
	_glory_presentations = GloryMonsterPresentationCatalogScript.new()
	if not _glory_presentations.load_default():
		_glory_presentations = null
	_death_effects = MonsterDeathEffectControllerScript.new()
	_death_effects.name = "MonsterDeathEffects"
	add_child(_death_effects)
	var effect_error := _death_effects.configure(_manifest, _world_parent)
	if effect_error != OK:
		_death_effects.queue_free()
		_death_effects = null
		return effect_error
	_death_effects.configure_glory(_ale_repository, _glory_presentations)
	_attack_effects = MonsterAttackEffectControllerScript.new()
	_attack_effects.name = "MonsterAttackEffects"
	add_child(_attack_effects)
	var attack_effect_error := _attack_effects.configure(_manifest, _world_parent)
	if attack_effect_error != OK:
		_attack_effects.queue_free()
		_attack_effects = null
		return attack_effect_error
	_attack_effects.configure_glory(_ale_repository, _glory_presentations)
	_sama_effects = SamaEffectController.new()
	add_child(_sama_effects)
	_sama_effects.configure(_world_parent, _local_player)
	return OK


## 每帧将视口鼠标位置换算为世界坐标，并刷新唯一的怪物悬浮目标。
## [param _delta] 当前渲染帧与上一帧之间的秒数；悬浮判定不依赖该值。
func _process(_delta: float) -> void:
	if _world_parent == null or not is_instance_valid(_world_parent):
		_set_hovered_entity("")
		return
	update_hover_at(_world_parent.get_global_mouse_position())


## 执行 `apply_snapshot` 对应的模块操作。
## [param combat_snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func apply_snapshot(combat_snapshot: Dictionary) -> void:
	var observed: Dictionary = {}
	for raw_monster: Variant in combat_snapshot.get("monsters", []):
		var monster: Dictionary = raw_monster
		var entity_id := String(monster["entity_id"])
		observed[entity_id] = true
		var view: MonsterWorldView = _views.get(entity_id)
		if view == null:
			view = MonsterWorldViewScript.new()
			view.name = "Monster_%s" % entity_id.replace(".", "_")
			_world_parent.add_child(view)
			var glory_presentation: Dictionary = {}
			if _glory_presentations != null:
				glory_presentation = _glory_presentations.definition_for_actor(
					String(monster["combat_actor_id"])
				)
			if view.configure(
				_manifest, monster, _ale_repository, glory_presentation
			) != OK:
				view.queue_free()
				continue
			_views[entity_id] = view
		else:
			view.apply_snapshot(monster)
	for entity_id: String in _views.keys():
		if observed.has(entity_id):
			continue
		var stale: MonsterWorldView = _views[entity_id]
		if entity_id == _hovered_entity_id:
			_hovered_entity_id = ""
		stale.queue_free()
		_views.erase(entity_id)
	_apply_recent_events(combat_snapshot)
	if _sama_effects != null: _sama_effects.apply_snapshot(combat_snapshot)
	if _attack_effects != null:
		_attack_effects.apply_corrosion_snapshot(combat_snapshot, _local_player)


## 执行 `nearest_target` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param radius] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func nearest_target(world_position: Vector2, radius: float = 72.0) -> String:
	var selected := ""
	var best_distance := radius
	for entity_id: String in _views:
		var view: MonsterWorldView = _views[entity_id]
		var distance := view.position.distance_to(world_position)
		if view.is_selectable_at(world_position, radius) and distance <= best_distance:
			selected = entity_id
			best_distance = distance
	return selected


## 按世界坐标刷新当前唯一悬浮怪物，复刻旧客户端的 `m_pShowNpcName` 语义。
## [param world_position] 鼠标换算后的世界坐标。
## 返回当前命中的怪物实体 ID；未命中时返回空字符串。
func update_hover_at(world_position: Vector2) -> String:
	var selected := ""
	var best_distance_squared := INF
	for entity_id: String in _views:
		var view: MonsterWorldView = _views[entity_id]
		if not view.is_hovered_at(world_position):
			continue
		var collision_center := view.position + view.visual_collision_offset
		var distance_squared := collision_center.distance_squared_to(world_position)
		if distance_squared < best_distance_squared:
			selected = entity_id
			best_distance_squared = distance_squared
	_set_hovered_entity(selected)
	return selected


## 执行 `target_position` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func target_position(entity_id: String) -> Vector2:
	var view: MonsterWorldView = _views.get(entity_id)
	return view.position if view != null and view.visible else Vector2.INF


## 执行 `first_visual_collision` 对应的模块操作。
## [param segment_start] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param segment_end] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func first_visual_collision(segment_start: Vector2, segment_end: Vector2) -> Dictionary:
	var best := {"hit": false, "t": INF}
	for view: MonsterWorldView in _views.values():
		var candidate: Dictionary = view.visual_segment_collision(segment_start, segment_end)
		if bool(candidate.get("hit", false)) and float(candidate.get("t", INF)) < float(best["t"]):
			best = candidate
	return best


## 执行 `clear` 对应的模块操作。
func clear() -> void:
	_set_hovered_entity("")
	for view: MonsterWorldView in _views.values():
		view.queue_free()
	_views.clear()
	_last_event_id = 0
	if _death_effects != null:
		_death_effects.clear()
	if _attack_effects != null:
		_attack_effects.clear()


## 在旧目标与新目标间原子切换名称可见性，保证全场最多显示一个怪物名。
## [param entity_id] 新悬浮怪物实体 ID；空字符串表示鼠标已离开全部怪物。
func _set_hovered_entity(entity_id: String) -> void:
	if entity_id == _hovered_entity_id:
		return
	var previous: MonsterWorldView = _views.get(_hovered_entity_id)
	if previous != null:
		previous.set_hovered(false)
	_hovered_entity_id = entity_id
	var current: MonsterWorldView = _views.get(_hovered_entity_id)
	if current != null:
		current.set_hovered(true)


## 执行 `apply_recent_events` 对应的模块操作。
## [param combat_snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：快照允许重发事件，客户端游标保证每个权威伤害只表现一次。
func _apply_recent_events(combat_snapshot: Dictionary) -> void:
	var events_value: Variant = combat_snapshot.get("recent_events", [])
	if not events_value is Array:
		return
	for raw_event: Variant in events_value:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event
		var event_id := int(event.get("event_id", 0))
		if event_id <= _last_event_id:
			continue
		_last_event_id = event_id
		var event_type := StringName(event.get("event_type", ""))
		if event.has("shot_id"):
			CombatTraceLogger.record(&"client", &"authoritative_projectile_event_observed", event)
		if event_type == &"sama_activated" and _sama_effects != null:
			_sama_effects.present_activation(event)
		if event_type == &"monster_attack_started" and _attack_effects != null:
			_attack_effects.present_attack(event)
		if event_type in [&"monster_attack_resolved", &"monster_attack_expired"] and _attack_effects != null:
			_attack_effects.settle_attack(event)
		if event_type in [
			&"energy_cannon_hit", &"rocket_launcher_hit", &"missile_hit", &"generator_heat_hit", &"sama_pulse_hit", &"sama_fission_hit", &"central_fatal_hit",
			&"monster_attack_resolved",
		]:
			_present_damage(event, combat_snapshot)
		if event_type == &"monster_attack_resolved":
			_present_attack_impact(event, combat_snapshot)
			_present_austin_effects(event, combat_snapshot)
		if event_type in [&"energy_cannon_hit", &"rocket_launcher_hit", &"missile_hit", &"generator_heat_hit", &"sama_pulse_hit", &"sama_fission_hit", &"central_fatal_hit"]:
			_present_nested_death(event)


## 表现一次权威伤害事件的飘字。
## [param event] 权威战斗事件。
## [param combat_snapshot] 用于识别本地玩家的快照。
func _present_damage(event: Dictionary, combat_snapshot: Dictionary) -> void:
	var damage := int(event.get("damage", 0))
	if damage <= 0:
		return
	var world_position := _damage_world_position(event, combat_snapshot)
	if not is_finite(world_position.x) or not is_finite(world_position.y):
		return
	var damage_float: Node2D = CombatDamageFloatScript.new()
	damage_float.name = "DamageFloat_%d" % int(event.get("event_id", 0))
	damage_float.position = world_position
	_world_parent.add_child(damage_float)
	if String(event.get("event_type", "")) == "sama_fission_hit":
		damage_float.present_status("核变爆炸 -%d" % damage, Color("ffa86c"))
	elif String(event.get("event_type", "")) == "central_fatal_hit":
		damage_float.position.y -= 22
		damage_float.present_status("致命一击 -%d" % damage, Color.WHITE)
	else:
		damage_float.present(damage)


## 只根据已去重的权威回执显示减伤和治疗，客户端不再判定概率。
## [param event] 怪物实际命中回执。[param snapshot] 当前战斗快照。
func _present_austin_effects(event: Dictionary, snapshot: Dictionary) -> void:
	var effects: Variant = event.get("austin_effects", [])
	if not effects is Array or effects.is_empty(): return
	var world_position := _damage_world_position(event, snapshot)
	if not world_position.is_finite(): return
	var index := 1
	for effect: Variant in effects:
		if not effect is Dictionary or effect.get("kind") not in ["mitigation", "healing"] or int(effect.get("amount", 0)) <= 0: continue
		var healing: bool = effect.kind == "healing"
		var view := CombatDamageFloat.new()
		view.position = world_position + Vector2(0, -24 * index)
		_world_parent.add_child(view)
		view.present_status("进化 +%d" % int(effect.amount) if healing else "光辉 减伤%d" % int(effect.amount), Color(0.4, 1, 0.6) if healing else Color(0.5, 0.9, 1))
		index += 1


## 解析权威伤害事件的世界表现位置，并允许目标节点已因死亡快照被移除。
## [param event] 包含目标、命中点及可选死亡子事件的权威伤害事件。
## [param combat_snapshot] 用于识别本地玩家的当前权威快照。
## 返回可绘制的世界坐标；事件缺少任何可信位置时返回无穷坐标。
## 设计：飘字是独立瞬时效果，不从属于怪物节点生命周期；最后一击仍使用服务端死亡脚点。
func _damage_world_position(event: Dictionary, combat_snapshot: Dictionary) -> Vector2:
	var anchor := _target_anchor(event, combat_snapshot)
	if anchor != null:
		return _world_parent.to_local(anchor.global_position)
	var death_value: Variant = event.get("death", {})
	if death_value is Dictionary:
		var death_position := _vector_from_pair((death_value as Dictionary).get("position", []))
		if is_finite(death_position.x) and is_finite(death_position.y):
			return death_position
	return _vector_from_pair(event.get("impact_position", []))


## 将网络事件中的二元素坐标数组转换为 Vector2。
## [param value] 期望为 `[x, y]` 的外部数据。
## 返回有效坐标；格式不合法时返回 `Vector2.INF`。
func _vector_from_pair(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2.INF
	var result := Vector2(float(value[0]), float(value[1]))
	return result if is_finite(result.x) and is_finite(result.y) else Vector2.INF


## 在普通怪物攻击权威结算时，于当前可见战车脚点播放受击覆盖效果。
## [param event] 怪物攻击结算事件。
## [param combat_snapshot] 用于识别本地玩家的快照。
func _present_attack_impact(event: Dictionary, combat_snapshot: Dictionary) -> void:
	if _attack_effects == null:
		return
	var anchor := _target_anchor(event, combat_snapshot)
	if anchor == null:
		return
	_attack_effects.present_impact(
		event,
		_world_parent.to_local(anchor.global_position),
	)


## 查找伤害事件对应的场景锚点。
## [param event] 权威伤害事件。
## [param combat_snapshot] 用于识别本地玩家的快照。
## 返回怪物视图或本地玩家节点。
func _target_anchor(event: Dictionary, combat_snapshot: Dictionary) -> Node2D:
	var target_entity_id := String(event.get("target_entity_id", ""))
	var anchor: Node2D = _views.get(target_entity_id)
	if anchor == null and target_entity_id == String(combat_snapshot.get("local_entity_id", "")):
		anchor = _local_player
	return anchor


## 从最后一击事件中提取独立 `monster_died` 生命周期事件并播放一次。
## [param event] 可能携带 `death` 子事件的能量炮命中事件。
func _present_nested_death(event: Dictionary) -> void:
	if _death_effects == null:
		return
	var death_value: Variant = event.get("death", {})
	if not death_value is Dictionary:
		return
	var death: Dictionary = death_value
	if StringName(death.get("event_type", "")) != &"monster_died":
		return
	var monster_id := String(death.get("monster_id", ""))
	var view: MonsterWorldView = _views.get(monster_id)
	if view == null:
		return
	var raw_position: Variant = death.get("position", [])
	if not raw_position is Array or (raw_position as Array).size() != 2:
		return
	_death_effects.present_death(
		monster_id,
		view.combat_actor_id,
		Vector2(float(raw_position[0]), float(raw_position[1])),
		int(death.get("death_generation", 0)),
	)
