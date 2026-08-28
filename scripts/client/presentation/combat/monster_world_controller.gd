class_name MonsterWorldController
extends Node

const MonsterWorldViewScript := preload("res://scripts/client/presentation/combat/monster_world_view.gd")

var _world_parent: Node2D
var _manifest: Dictionary = {}
var _views: Dictionary = {}


## Configures the controller with [param world_parent] and business [param manifest].
## [param world_parent] Y-sorted scene parent that owns each monster view directly.
## [param manifest] Combat visual manifest used only for rendering actor IDs from snapshots.
## Returns `OK` when dependencies are available.
func configure(world_parent: Node2D, manifest: Dictionary) -> Error:
	if world_parent == null or manifest.is_empty():
		return ERR_INVALID_PARAMETER
	_world_parent = world_parent
	_manifest = manifest.duplicate(true)
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


## Removes every map-scoped monster presentation.
func clear() -> void:
	for view: MonsterWorldView in _views.values():
		view.queue_free()
	_views.clear()
