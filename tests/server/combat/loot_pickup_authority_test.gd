extends SceneTree

const PEER := 91
const MATERIAL := "low_grade_gel"
const BURST_SIZE := 60

var failures: Array[String] = []
var checks := 0
var seen_ids: Array[String] = []


## 在内容挂载后启动隔离存档的连续拾取回归。
func _initialize() -> void:
	call_deferred("_run")


## 验证旧编号兼容、无等待连续入账、重启、重试以及失败不吞物品。
func _run() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = "res://data/maps/d04_field_zone.json"
	config.player_state_store_path = "res://.godot/loot-pickup-%d.json" % Time.get_ticks_usec()
	for generation in range(2):
		var server := AuthoritativeServer.new()
		_expect(server.initialize(config).ok, "服务器加载隔离存档")
		for peer in [PEER, PEER + 1]:
			_expect(server.open_session(peer, {"protocol_version": config.protocol_version,
				"content_version": config.content_version}, 1000).ok, "创建两个真实拾取会话")
		var session := server.sessions.session_for_peer(PEER)
		var map := server.map_registry.instance_by_id(session.map_instance_id)
		var module := map.combat_module
		var monster: MonsterLifecycle = module.monsters.values()[0]
		monster.position = map.entities[session.entity_id].position
		monster.death_generation = 1
		monster.drop_table.configure([{"item_definition_id": MATERIAL, "chance": 1.0,
			"minimum_quantity": 2, "maximum_quantity": 2}])
		if generation == 0:
			# 模拟旧版真实存档中的首份掉落，不能通过清空背包来解决冲突。
			var legacy := server.player_panel_service.grant_loot(server.autosave_service.state_for(session.entity_id),
				{"loot_id": "%s.loot.1.1" % monster.monster_id, "item_definition_id": MATERIAL, "quantity": 1})
			_expect(legacy.is_ok, "旧版掉落编号可正常还原")
			_expect(server.autosave_service.commit_player_state(session.entity_id, legacy.value.candidate).is_ok,
				"保存旧版物品用于冲突复现")
		_expect(_quantity(server.autosave_service.state_for(session.entity_id), MATERIAL) == 1 + generation * BURST_SIZE * 2,
			"重启保留此前全部材料")
		var picked_id := ""
		for index in range(BURST_SIZE):
			var loot: Dictionary = module._spawn_monster_loot(monster, session.entity_id)[0]
			picked_id = loot.loot_id
			_expect(not seen_ids.has(picked_id), "连续掉落及重启后编号均不复用")
			seen_ids.append(picked_id)
			var result := server.handle_peer_loot_pickup(PEER, {"loot_id": picked_id})
			_expect(result.ok, "同一帧第%d次拾取入账成功：%s" % [index, result.get("code", "")])
			_expect(not module.ground_loot.has(picked_id), "成功入账才移除对应地面物品")
		var current := server.autosave_service.state_for(session.entity_id)
		_expect(_quantity(current, MATERIAL) == 1 + (generation + 1) * BURST_SIZE * 2,
			"连续拾取准确累计并跨满堆叠创建新堆")
		var before_retry := current.to_dictionary()
		for peer in [PEER, PEER + 1]:
			var retry := server.handle_peer_loot_pickup(peer, {"loot_id": picked_id})
			_expect(not retry.ok and retry.code == &"loot.not_found", "重试或另一账号抢同一掉落不能重复入账")
		_expect(server.autosave_service.state_for(session.entity_id).to_dictionary() == before_retry,
			"拒绝重试不改变背包及版本")
		var duplicate := server.player_panel_service.grant_loot(current, {
			"loot_id": current.inventory_stacks[0].stack_id, "item_definition_id": MATERIAL, "quantity": 1})
		_expect(not duplicate.is_ok and duplicate.error_code == &"inventory.duplicate_item", "仍拒绝真正重复的物品实例")
		_test_failed_pickup(server, session, monster)
		_test_module_identity(module, monster, session.entity_id)
		server.stop_network()
		server.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	for failure: String in failures:
		push_error(failure)
	print("LOOT_PICKUP_AUTHORITY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 背包容量拒绝保留地面实体，扩容后重试同一编号只入账一次。
## [param server] 隔离服务器。
## [param session] 当前玩家的真实会话。
## [param monster] 靠近玩家的测试掉落来源。
func _test_failed_pickup(server: AuthoritativeServer, session: ServerSession, monster: MonsterLifecycle) -> void:
	var current := server.autosave_service.state_for(session.entity_id)
	var old_capacity := current.inventory_capacity
	current.inventory_capacity = current.inventory_stacks.size()
	_expect(server.autosave_service.commit_player_state(session.entity_id, current).is_ok, "临时填满背包容量")
	var module := server.map_registry.instance_by_id(session.map_instance_id).combat_module
	monster.drop_table.configure([{"item_definition_id": "recruit_energy_cannon", "chance": 1.0,
		"minimum_quantity": 1, "maximum_quantity": 1}])
	var loot: Dictionary = module._spawn_monster_loot(monster, session.entity_id)[0]
	var result := server.handle_peer_loot_pickup(PEER, {"loot_id": loot.loot_id})
	_expect(not result.ok and module.ground_loot.has(loot.loot_id), "背包满时不能吞掉掉落")
	current = server.autosave_service.state_for(session.entity_id)
	current.inventory_capacity = old_capacity
	_expect(server.autosave_service.commit_player_state(session.entity_id, current).is_ok, "恢复测试背包容量")
	_expect(server.handle_peer_loot_pickup(PEER, {"loot_id": loot.loot_id}).ok, "失败后同一掉落可重试入账")


## 地图独立实例和同一模块重建均不能复用旧编号，且不改变随机掉落结果。
## [param source] 实际地图中的战斗模块。
## [param monster] 编号、死亡代数和地图均相同的来源。
## [param actor_id] 仅供生成掉落的归属信息。
func _test_module_identity(source: AuthoritativeCombatModule, monster: MonsterLifecycle, actor_id: String) -> void:
	var isolated := AuthoritativeCombatModule.new()
	var prior := source._spawn_monster_loot(monster, actor_id)[0] as Dictionary
	for _round in range(2):
		isolated.configure(20, 100)
		var next := isolated._spawn_monster_loot(monster, actor_id)[0] as Dictionary
		_expect(next.loot_id != prior.loot_id, "独立模块及重新配置获得新命名空间")
		_expect(next.item_definition_id == prior.item_definition_id and next.quantity == prior.quantity,
			"身份生成不参与玩法随机数或改变物品数量")
		prior = next


## 汇总存档中指定材料的全部堆叠。
## [param state] 当前持久化记录。
## [param definition_id] 物品定义标识。
## 返回背包内的总数量。
func _quantity(state: PlayerStateRecord, definition_id: String) -> int:
	var total := 0
	for stack: InventoryStackRecord in state.inventory_stacks:
		if stack.item_definition_id == definition_id:
			total += stack.quantity
	return total


## 累计事务断言并收集失败原因。
## [param condition] 必须成立的条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
