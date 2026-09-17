extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
var items := ItemCatalog.new()
var service := AuthoritativeCommerceService.new()
var mapper: PlayerStateMapper
var fixture := Fixture.new()
var checks := 0
var failures: Array[String] = []


## 延迟运行以便正式内容目录初始化完成。
func _initialize() -> void:
	call_deferred("_run")


## 验证权威扣费、穿戴与背包存档、恶意意图拒绝及合成原子性。
func _run() -> void:
	_expect(items.initialize().is_ok and fixture.initialize().is_ok and service.initialize().is_ok, "正式目录和服务初始化")
	mapper = PlayerStateMapper.new(items)
	for installed: bool in [false, true]:
		var player := _player()
		if installed:
			_expect(player.equip_character_item("inventory.training_shirt", "upper_body", player.inventory.revision, player.revision).is_ok, "穿上目标服装")
		var stone := _give(player, "enhancement:gem:movement_speed:3", "stone", 2)
		stone.bound = true
		var state: PlayerStateRecord = mapper.to_record(player).value
		var before := state.to_dictionary()
		var command := _command(state, "enhance_clothing")
		command["rank"] = 15
		command["price"] = 0
		var result := service.execute(state, command)
		_expect(result.is_ok and state.to_dictionary() == before, "只修改隔离候选，不信任客户端价格等级")
		if not result.is_ok:
			failures.append(result.error_message)
			continue
		var candidate: PlayerStateRecord = result.value.candidate
		var decoded := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(candidate.to_dictionary())))
		_expect(decoded.is_ok, "JSON存档往返")
		var restored: Player = mapper.to_domain(decoded.value).value
		var shirt := PlayerEnhancementActions.clothing(restored, "inventory.training_shirt")
		_expect(shirt.enhancement.gem_stage == 1 and shirt.bound, "高级石打空装备仅一段且绑定保留")
		_expect(candidate.currency == state.currency - 100 and restored.inventory.find("stone").quantity == 1, "精确扣一颗石头与100星际币")
		_expect(not service.execute(candidate, command).is_ok, "背包版本阻止同一请求重放")
		var current := CurrentPlayer.new()
		_expect(current.apply_bundle(result.value.panel_bundle), "客户端恢复服务端快照")
		_expect(PlayerEnhancementActions.clothing(current, "inventory.training_shirt").enhancement.gem_stage == 1, "客户端背包及穿着保留强化")
	_test_failures()
	_test_synthesis()
	_test_transfer()
	_test_live_server()
	for failure: String in failures:
		push_error(failure)
	print("CLOTHING_ENHANCEMENT_AUTHORITY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 对失败分支逐个确认材料、金币、穿着和状态均不变。
func _test_failures() -> void:
	for failure: String in ["missing_clothing", "locked_clothing", "locked_stone", "poor", "revision", "route"]:
		var player := _player()
		var shirt := PlayerEnhancementActions.clothing(player, "inventory.training_shirt")
		var stone := _give(player, "enhancement:gem:movement_speed:3", "stone", 1)
		if failure == "locked_clothing":
			shirt.locked = true
		elif failure == "locked_stone":
			stone.locked = true
		elif failure == "poor":
			player.inventory.currency = 99
		elif failure == "route":
			shirt.enhancement.apply_stone(items.create("enhancement:gem:max_health:1", {}).value)
		var state: PlayerStateRecord = mapper.to_record(player).value
		var command := _command(state, "enhance_clothing")
		if failure == "missing_clothing":
			command.instance_id = "not-owned"
		if failure == "revision":
			command.state_revision = -1
		var before := state.to_dictionary()
		_expect(not service.execute(state, command).is_ok and state.to_dictionary() == before, "拒绝且不改动：" + failure)


## 合成可跨堆叠消费，失败须恢复全部材料，绑定产物不可洗白。
func _test_synthesis() -> void:
	var player := _player()
	var stone := _give(player, "enhancement:gem:defense:10", "stone", 2)
	stone.bound = true
	var state: PlayerStateRecord = mapper.to_record(player).value
	var result := service.execute(state, _command(state, "synthesize_enhancement"))
	_expect(result.is_ok, "十级宝石二合一")
	if result.is_ok:
		var next: Player = mapper.to_domain(result.value.candidate).value
		_expect(next.inventory.count_definition("enhancement:gem:defense:11") == 1 and next.inventory.count_definition(stone.definition_id) == 0, "产出十一级且扣两个十级")
		for item: GameItem in next.inventory.items():
			if item is EnhancementStone:
				_expect(item.bound, "合成保留绑定")
	player.inventory.capacity = player.inventory.items().size()
	stone.quantity = 3
	var before: Dictionary = mapper.to_record(player).value.to_dictionary()
	var product: EnhancementStone = items.create(stone.next_definition_id(), {"instance_id": "product"}).value
	_expect(not PlayerEnhancementActions.synthesize(player, stone, product, player.inventory.revision, player.revision).is_ok, "背包满且原堆叠未清空时拒绝")
	_expect(mapper.to_record(player).value.to_dictionary() == before, "合成失败回滚原堆叠和金币")


## 迁移清空来源并保留其他词条，重复意图不能复制宝石。
func _test_transfer() -> void:
	var player := _player()
	var source := PlayerEnhancementActions.clothing(player, "inventory.training_shirt")
	source.enhancement.apply_stone(items.create("enhancement:gem:max_health:1", {}).value)
	source.enhancement.apply_stone(items.create("enhancement:prefix:tiger:4", {}).value)
	var target: Clothing = items.create("male_sleeveless_shirt", {"instance_id": "target"}).value
	player.receive_loot(target)
	var revision := player.inventory.revision
	_expect(PlayerEnhancementActions.transfer(player, source.instance_id, target.instance_id, revision, player.revision).is_ok, "同部位路线迁移")
	_expect(source.enhancement.gem_stage == 0 and source.enhancement.prefix_quality == 4 and target.enhancement.gem_stage == 1, "迁移不复制且保留来源前缀")
	_expect(not PlayerEnhancementActions.transfer(player, source.instance_id, target.instance_id, revision, player.revision).is_ok, "迁移重放被拒绝")


## 创建拥有可操作服装及足量测试金币的隔离玩家。
## 返回从内存夹具还原的玩家。
func _player() -> Player:
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory.currency = 100000
	return player


## 把正式目录材料放入隔离玩家背包。
## [param player] 测试聚合。
## [param definition] 正式材料身份。
## [param id] 测试实例身份。
## [param amount] 测试材料数量。
## 返回入包材料。
func _give(player: Player, definition: String, id: String, amount: int) -> EnhancementStone:
	var item: EnhancementStone = items.create(definition, {"instance_id": id, "quantity": amount}).value
	_expect(player.receive_loot(item).is_ok, "材料入包")
	return item


## 构造仅包含意图与版本的客户端请求。
## [param state] 当前权威状态。
## [param action] 操作类型。
## 返回对应版本命令。
func _command(state: PlayerStateRecord, action: String) -> Dictionary:
	return {"type": action, "instance_id": "inventory.training_shirt", "stone_id": "stone",
		"inventory_revision": state.inventory_revision, "state_revision": state.revision}


## 记录实际行为断言。
## [param condition] 预期条件。
## [param message] 中文失败描述。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


## 通过真实会话命令在野外强化，保持实时资源、武器冷却并立即更新移动属性。
func _test_live_server() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = "res://data/maps/d04_field_zone.json"
	config.player_state_store_path = "res://.godot/clothing-live-%d.json" % Time.get_ticks_usec()
	var server := AuthoritativeServer.new()
	_expect(server.initialize(config).ok, "野外隔离服务器初始化")
	var opened := server.open_session(91, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000)
	_expect(opened.ok, "正式玩家会话可进入野外")
	var session := server.sessions.session_for_peer(91)
	var record := server.autosave_service.state_for(session.entity_id)
	var player: Player = mapper.to_domain(record).value
	player.inventory.currency = 100000
	var shirt: Clothing = items.create("male_sleeveless_shirt", {"instance_id": "live-shirt"}).value
	player.receive_loot(shirt)
	player.equip_character_item(shirt.instance_id, "upper_body", player.inventory.revision, player.revision)
	_give(player, "enhancement:gem:movement_speed:1", "live-stone", 2)
	server.autosave_service.commit_player_state(session.entity_id, mapper.to_record(player).value)
	var map := server.map_registry.instance_by_id(session.map_instance_id)
	_expect(map.is_vehicle_combat_active(), "在真实战斗地图验证")
	var runtime := map.vehicle_combat_state_for(session.entity_id)
	runtime.health = 23
	runtime.working_energy = 17
	var actor: Dictionary = map.combat_module.actors[session.entity_id]
	actor.cooldown_ready_ticks["energy_cannon.primary"] = 999
	var old_speed: float = map.entities[session.entity_id].movement_speed
	record = server.autosave_service.state_for(session.entity_id)
	var command := {"type": "enhance_clothing", "instance_id": "live-shirt", "stone_id": "live-stone",
		"state_revision": record.revision, "inventory_revision": record.inventory_revision}
	var result := server.handle_peer_player_panel_command(91, command)
	_expect(result.ok, "真实命令入口可完成强化")
	_expect(runtime == map.vehicle_combat_state_for(session.entity_id) and runtime.health == 23 and runtime.working_energy == 17, "强化保留实际战车对象及实时资源")
	_expect(actor.cooldown_ready_ticks["energy_cannon.primary"] == 999, "野外强化不重置冷却")
	_expect(is_equal_approx(map.entities[session.entity_id].movement_speed, minf(240, old_speed + 2)), "宝石立即影响实际地图速度")
	var saved := server.autosave_service.state_for(session.entity_id)
	_expect(PlayerEnhancementActions.clothing(mapper.to_domain(saved).value, "live-shirt").enhancement.gem_stage == 1, "强化写回真实仓储")
	_expect(not server.handle_peer_player_panel_command(91, command).ok, "真实会话拒绝旧版本强化重放")
	server.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
