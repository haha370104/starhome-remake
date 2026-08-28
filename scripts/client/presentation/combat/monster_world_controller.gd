class_name MonsterWorldController
extends Node

const MonsterWorldViewScript := preload("res://scripts/client/presentation/combat/monster_world_view.gd")
const CombatDamageFloatScript := preload("res://scripts/client/presentation/combat/combat_damage_float.gd")

var _world_parent: Node2D
var _manifest: Dictionary = {}
var _views: Dictionary = {}
var _local_player: Node2D
var _last_event_id := 0


## Configures the controller with [param world_parent], business [param manifest] and [param local_player].
## [param world_parent] Y-sorted scene parent that owns each monster view directly.
## [param manifest] Combat visual manifest used only for rendering actor IDs from snapshots.
## [param local_player] Local authority actor presentation used only as a damage-number anchor.
## Returns `OK` when dependencies are available.
func configure(world_parent: Node2D, manifest: Dictionary, local_player: Node2D) -> Error:
	if world_parent == null or manifest.is_empty() or local_player == null:
		return ERR_INVALID_PARAMETER
	_world_parent = world_parent
	_manifest = manifest.duplicate(true)
	_local_player = local_player
	return OK


## Reconciles all visible monsters from one authoritative [param combat_snapshot].
## [param combat_snapshot] Validated map-scoped combat document containing a monster list.
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
			if view.configure(_manifest, monster) != OK:
				view.queue_free()
				continue
			_views[entity_id] = view
		else:
			view.apply_snapshot(monster)
	for entity_id: String in _views.keys():
		if observed.has(entity_id):
			continue
		var stale: MonsterWorldView = _views[entity_id]
		stale.queue_free()
		_views.erase(entity_id)
	_apply_recent_events(combat_snapshot)


## Finds the living monster closest to [param world_position] within [param radius].
## [param world_position] Player click coordinate used for local target selection only.
## [param radius] Maximum selection distance; the server still performs range and life validation.
## Returns the selected monster ID or an empty string.
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


## Resolves the latest authority position for [param entity_id].
## [param entity_id] Monster identity selected from this controller's reconciled views.
## Returns the world foot point, or `Vector2.INF` when the target is absent.
func target_position(entity_id: String) -> Vector2:
	var view: MonsterWorldView = _views.get(entity_id)
	return view.position if view != null and view.visible else Vector2.INF


## 返回 [param segment_start] 到 [param segment_end] 最先穿过的可见怪物表现碰撞。
## Returns 命中信息或 `hit=false`；结果仅供弹体特效使用。
func first_visual_collision(segment_start: Vector2, segment_end: Vector2) -> Dictionary:
	var best := {"hit": false, "t": INF}
	for view: MonsterWorldView in _views.values():
		var candidate: Dictionary = view.visual_segment_collision(segment_start, segment_end)
		if bool(candidate.get("hit", false)) and float(candidate.get("t", INF)) < float(best["t"]):
			best = candidate
	return best


## Removes every map-scoped monster presentation.
func clear() -> void:
	for view: MonsterWorldView in _views.values():
		view.queue_free()
	_views.clear()
	_last_event_id = 0


## 消费 [param combat_snapshot] 中带单调事件号的最近战斗事件并生成一次性飘字。
## Design: 快照允许重发事件，客户端游标保证每个权威伤害只表现一次。
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
		var target_entity_id := String(event.get("target_entity_id", ""))
		var anchor: Node2D = _views.get(target_entity_id)
		if anchor == null and target_entity_id == String(combat_snapshot.get("local_entity_id", "")):
			anchor = _local_player
		if anchor == null:
			continue
		var damage_float: Node2D = CombatDamageFloatScript.new()
		anchor.add_child(damage_float)
		damage_float.present(int(event.get("damage", 0)))
