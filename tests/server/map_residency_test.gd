extends SceneTree

const ServerScript := preload("res://scripts/server/authoritative_server.gd")
const ConfigScript := preload("res://scripts/server/server_config.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
var failures := PackedStringArray()
var assertions := 0


## 验证按玩家加载、最后离开休眠、导航释放和领域状态跨休眠保留。
func _initialize() -> void:
	var config := ConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = false
	var server := ServerScript.new()
	_expect(server.initialize(config).ok, "服务器初始化应成功")
	_expect(server.map_registry.all_instances().is_empty(), "无人时不能加载运行地图")
	for peer in [2, 3]:
		_expect(server.open_session(peer, {"protocol_version": Protocol.PROTOCOL_VERSION,
			"content_version": Protocol.PUBLIC_CONTENT_VERSION}, 0).ok, "测试玩家应加入")
	var hall := server.map_instance
	_expect(server.map_registry.all_instances().size() == 1, "同图两人应只加载一个实例")
	var field: AuthoritativeMapInstance = server.ensure_runtime_map("d04_field_zone").value
	_move_player(server, 2, field, Vector2(1500, 1450))
	_move_player(server, 3, field, Vector2(1600, 1450))
	server.advance_simulation(0.05, 0)
	_expect(hall.navigation == null, "最后一人离开大厅应释放大厅导航")
	_expect(server.map_registry.all_instances().size() == 1, "只有当前有人野外图保持活跃")
	var navigation_reference: WeakRef = weakref(field.navigation)
	var monster_id: String = field.combat_module.monsters.keys()[0]
	var monster: MonsterLifecycle = field.combat_module.monsters[monster_id]
	monster.apply_damage(1, "fixture", field.combat_module.current_tick)
	var remaining_health := monster.health
	var source = field.mining_module.sources.values()[0]
	var source_id: String = source.source_id
	source.extract(7)
	var remaining_minerals: int = source.remaining
	field.combat_module.ground_loot["retained.loot"] = {
		"loot_id": "retained.loot", "map_instance_id": field.instance_id,
		"source_monster_id": monster_id, "killer_id": "fixture",
		"item_definition_id": "fixture.item", "quantity": 2,
		"position": [monster.position.x, monster.position.y], "spawn_tick": 0,
	}
	var awakened_hall: AuthoritativeMapInstance = server.ensure_runtime_map("yian_harbor_hall_floor_1").value
	_move_player(server, 2, awakened_hall, config.default_spawn)
	server.advance_simulation(0.05, 0)
	_expect(field.navigation != null, "另一玩家仍在地图时不能休眠")
	_move_player(server, 3, awakened_hall, config.default_spawn + Vector2(80, 0))
	server.advance_simulation(0.05, 0)
	_expect(field.navigation == null, "最后一人离开后应释放导航")
	_expect(navigation_reference.get_ref() == null, "采矿或回调不能偷偷保留旧导航引用")
	_expect(server.map_registry.instance_by_map_id("d04_field_zone") == null, "休眠地图不能参与活跃地图遍历")
	var paused_tick := field.combat_module.current_tick
	var paused_position := monster.position
	# 模拟休眠期间有怪物空位；返回时应按正常补量收敛，不重置现有实体。
	var missing: Array = field.combat_module.monsters.keys().slice(1, 21)
	for removed_id: String in missing:
		field.combat_module.monsters.erase(removed_id)
	server.advance_simulation(360.0, 0)
	_expect(field.combat_module.current_tick == paused_tick, "休眠地图不应逐 tick 模拟")
	_expect(monster.position == paused_position, "无人时不应继续游荡寻路")
	var resumed: AuthoritativeMapInstance = server.ensure_runtime_map("d04_field_zone").value
	_expect(resumed == field and resumed.navigation != null, "返回应重建导航并复用领域状态")
	_expect(monster.health == remaining_health, "切图不能重置怪物生命")
	_expect(resumed.mining_module.sources[source_id].remaining == remaining_minerals, "切图不能补满未采完矿点")
	_expect(resumed.combat_module.ground_loot["retained.loot"]["quantity"] == 2, "休眠不能吞掉掉落物")
	_expect(resumed.combat_module.monsters.size() == 100, "六分钟后应按补量规则补足种群")
	_expect(resumed.combat_module.current_tick >= paused_tick + 7200, "唤醒应一次性补算经过的时钟")
	resumed.combat_module.pending_projectiles.append({"fixture": true})
	_expect(not resumed.can_suspend_runtime(), "在途炮弹未结算前不能休眠")
	resumed.combat_module.pending_projectiles.clear()
	resumed.combat_module.pending_monster_attacks.append({"fixture": true})
	_expect(not resumed.can_suspend_runtime(), "在途怪物攻击未结算前不能休眠")
	resumed.combat_module.pending_monster_attacks.clear()
	_expect(resumed.can_suspend_runtime(), "无人且在途行为结算完后可以休眠")
	resumed.suspend_runtime(server.server_tick)
	server.free()
	if failures.is_empty():
		print("MAP_RESIDENCY_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 在测试中模拟一次已通过传送校验的玩家迁移。
## [param server] 被测权威服务器。
## [param peer] 待迁移的测试连接。
## [param target] 已按需加载的目标实例。
## [param position] 目标地图内的候选出生点。
func _move_player(server: AuthoritativeServer, peer: int, target: AuthoritativeMapInstance, position: Vector2) -> void:
	var session := server.sessions.session_for_peer(peer)
	var old := server.map_registry.instance_by_id(session.map_instance_id)
	_expect(target.spawn_entity(session.entity_id, target.admitted_spawn_position(position), 200.0).ok, "目标地图应接受实体")
	old.remove_entity(session.entity_id)
	session.map_instance_id = target.instance_id


## 记录一项断言。
## [param condition] 预期条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
