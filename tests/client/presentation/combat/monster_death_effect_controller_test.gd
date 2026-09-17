extends SceneTree

const MonsterWorldControllerScript := preload(
	"res://scripts/client/presentation/combat/monster_world_controller.gd"
)
const MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"

var assertions := 0
var failures: Array[String] = []


## 延迟执行需要节点树生命周期的死亡特效集成测试。
func _init() -> void:
	call_deferred("_run")


## 验证死亡事件隐藏本体、在原脚点播放素材，并按代际去重。
func _run() -> void:
	var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_expect(manifest_value is Dictionary, "combat manifest should parse")
	if not manifest_value is Dictionary:
		_finish()
		return
	var world := Node2D.new()
	world.name = "World"
	root.add_child(world)
	var local_player := Node2D.new()
	local_player.name = "LocalPlayer"
	world.add_child(local_player)
	var controller = MonsterWorldControllerScript.new()
	root.add_child(controller)
	_expect(controller.configure(world, manifest_value, local_player) == OK, "monster controller should load death effects")
	controller.apply_snapshot(_snapshot(true, 60, []))
	var monster := world.get_node_or_null("Monster_monster_om") as Node2D
	_expect(monster != null and monster.visible, "living monster should be visible")
	controller.apply_snapshot(_snapshot(false, 0, [_death_hit_event(1, 1)]))
	_expect(monster != null and not monster.visible, "authoritative death snapshot should hide the body")
	var lethal_damage := world.get_node_or_null("DamageFloat_1") as Node2D
	_expect(lethal_damage != null and lethal_damage.position == Vector2(140.0, 220.0),
		"最后一击应在怪物节点移除后仍按权威死亡脚点显示扣血")
	var effects := controller.get_node_or_null("MonsterDeathEffects")
	_expect(effects != null and effects.active_effect_count() == 1, "death should create one independent effect")
	var effect := world.get_node_or_null("MonsterDeath_monster_om_1") as Node2D
	_expect(effect != null and effect.position == Vector2(140.0, 220.0), "death effect should use the authoritative foot point")
	controller.apply_snapshot(_snapshot(false, 0, [_death_hit_event(1, 1)]))
	_expect(effects.active_effect_count() == 1, "replayed event id should not duplicate the effect")
	controller.apply_snapshot(_snapshot(true, 60, [_death_hit_event(1, 1)]))
	controller.apply_snapshot(_snapshot(false, 0, [_death_hit_event(2, 2)]))
	_expect(effects.active_effect_count() == 2, "new death generation should play independently")
	effects.advance(0.71)
	_expect(effects.active_effect_count() == 0, "seven frames at ten fps should finish after 0.7 seconds")
	local_player.position = Vector2(300.0, 180.0)
	controller.apply_snapshot(_snapshot(true, 60, [_contact_hit_event(3)]))
	var attack_effects := controller.get_node_or_null("MonsterAttackEffects")
	_expect(
		attack_effects != null and attack_effects.active_impact_count() == 1,
		"contact damage event should create one vehicle overlay",
	)
	var contact_impact := world.get_node_or_null(
		"MonsterImpact_monster_orb_attack_1"
	) as Node2D
	_expect(
		contact_impact != null and contact_impact.position == local_player.position,
		"contact overlay should appear at the local vehicle position",
	)
	controller.clear()
	controller.queue_free()
	world.queue_free()
	_finish()


## 构造单怪物权威快照。
## [param alive] 怪物是否存活。
## [param health] 当前生命值。
## [param events] 短事件窗口。
## 返回可供表现层消费的快照。
func _snapshot(alive: bool, health: int, events: Array) -> Dictionary:
	return {
		"server_tick": 10,
		"local_entity_id": "player.local",
		"monsters": [{
			"entity_id": "monster.om",
			"species_id": "om_adult",
			"display_name": "奥姆虫",
			"combat_actor_id": "om_adult_standard",
			"position": [140.0, 220.0],
			"health": health,
			"max_health": 60,
			"alive": alive,
			"action": "idle",
			"facing_index": 0,
		}],
		"recent_events": events,
	}


## 构造携带独立死亡生命周期子事件的最后一击事件。
## [param event_id] 战斗事件序号。
## [param generation] 怪物死亡代际。
## 返回事件字典。
func _death_hit_event(event_id: int, generation: int) -> Dictionary:
	return {
		"event_id": event_id,
		"event_type": "energy_cannon_hit",
		"target_entity_id": "monster.om",
		"damage": 7,
		"death": {
			"event_type": "monster_died",
			"monster_id": "monster.om",
			"death_generation": generation,
			"position": [140.0, 220.0],
		},
	}


## 构造感光质贴身攻击的权威伤害事件。
## [param event_id] 战斗事件序号。
## 返回事件字典。
func _contact_hit_event(event_id: int) -> Dictionary:
	return {
		"event_id": event_id,
		"event_type": "monster_attack_resolved",
		"attack_id": "monster.orb.attack.1",
		"attacker_id": "monster.orb",
		"target_entity_id": "player.local",
		"attack_archetype": "contact_melee",
		"combat_actor_id": "photosensitive_orb_standard",
		"damage": 3,
	}


## 记录布尔断言结果。
## [param condition] 期望条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出测试汇总并设置进程退出码。
func _finish() -> void:
	if failures.is_empty():
		print("MONSTER_DEATH_EFFECTS_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MONSTER_DEATH_EFFECTS_FAILED (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
