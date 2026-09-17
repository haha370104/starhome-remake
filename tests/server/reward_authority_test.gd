extends SceneTree

var failures: Array[String] = []
var checks := 0


## 延迟至内容挂载后验证真实服务器的账号倍率与拾取事务。
func _initialize() -> void:
	call_deferred("_run")


## 验证统一切面贯穿经验、生产、怪物掉落和持久化边界。
func _run() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.player_state_store_path = "res://.godot/reward-authority-%d.json" % Time.get_ticks_usec()
	var server := AuthoritativeServer.new()
	_expect(server.initialize(config).ok, "服务器加载奖励配置")
	for peer in [71, 72]:
		_expect(server.open_session(peer, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 0).ok, "两个独立账号加入")
	var first: ServerSession = server.sessions.session_for_peer(71)
	var second: ServerSession = server.sessions.session_for_peer(72)
	var state := server.autosave_service.state_for(first.entity_id)
	var other := server.autosave_service.state_for(second.entity_id)
	var rows: Array[RewardModifier] = []
	for raw: Dictionary in [
		{"id": "test.vip.xp", "channel": "experience", "multiplier": 2.5, "account_ids": [state.account_id], "skill_ids": ["mining", "refining"]},
		{"id": "test.vip.loot", "channel": "drop", "multiplier": 2.5, "account_ids": [state.account_id], "item_ids": ["low_grade_gel"]}
	]:
		rows.append(RewardModifier.parse(raw).value)
	server.reward_service.pipeline.add_provider(RewardModifierProvider.new(rows))
	state.character_skills["mining"] = {"level": 100, "current_exp": 0, "fractional_exp": 0.0}
	state.food_status = {"physical": 100, "cooldowns": {}, "active": [FoodEffect.new({"kind": 5, "amount": 20,
		"duration": 600, "expires_at": int(Time.get_unix_time_from_system()) + 600}).to_dictionary()]}
	var event := {"source": "authoritative_action", "skill_id": "mining", "amount": 0.1,
		"account_id": other.account_id, "multiplier": 999, "now": 0}
	for _index in range(5):
		var previous := state.to_dictionary()
		var granted := server.player_panel_service.grant_skill_progression(state, event)
		_expect(granted.is_ok and state.to_dictionary() == previous, "经验事务不修改输入状态且忽略伪造倍率")
		_expect(is_equal_approx(granted.value.progression.granted_experience, 0.3), "VIP与食品统一相乘且只应用一次")
		state = granted.value.candidate
	_expect(int(state.character_skills.mining.current_exp) == 1 and is_equal_approx(state.character_skills.mining.fractional_exp, 0.5), "小数经验累积无丢失")
	var ordinary := server.player_panel_service.grant_skill_progression(other, event)
	_expect(is_equal_approx(ordinary.value.progression.granted_experience, 0.1), "相同事件不能借用其他账号VIP")
	event.skill_id = "repair"
	_expect(is_equal_approx(server.player_panel_service.grant_skill_progression(state, event).value.progression.granted_experience, 0.1), "非指定技能保持基础经验")
	var restored := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(state.to_dictionary())))
	_expect(restored.is_ok, "倍率后的经验与食品状态可存档往返")
	_test_manufacturing(server, state)
	var instance: AuthoritativeMapInstance = server.ensure_runtime_map("d04_field_zone").value
	_expect(instance.combat_module.rewards == server.reward_service, "惰性地图使用同一权威奖励服务")
	var monster: MonsterLifecycle = instance.combat_module.monsters.values()[0]
	monster.drop_table.configure([
		{"item_definition_id": "low_grade_gel", "chance": 1.0, "minimum_quantity": 80, "maximum_quantity": 80},
		{"item_definition_id": "low_grade_energy_pack", "chance": 1.0, "minimum_quantity": 1, "maximum_quantity": 1}])
	var spawned := instance.combat_module._spawn_monster_loot(monster, first.entity_id)
	var total := 0
	var item_catalog := ItemCatalog.new()
	item_catalog.initialize()
	var receiver: Player = PlayerStateMapper.new(item_catalog).to_domain(other).value
	receiver.inventory.restore_items([])
	for loot: Dictionary in spawned:
		_expect(int(loot.quantity) <= int(item_catalog.definition(loot.item_definition_id).max_stack), "超堆叠奖励拆成可拾取数量")
		var granted := server.player_panel_service.grant_loot(PlayerStateMapper.new(item_catalog).to_record(receiver).value, loot)
		_expect(granted.is_ok, "每一份拆包奖励可通过真实入包事务")
		receiver = PlayerStateMapper.new(item_catalog).to_domain(granted.value.candidate).value
		if loot.item_definition_id == "low_grade_gel":
			total += int(loot.quantity)
	_expect(total == 160 or total == 240, "250%掉率为保证两份并50%追加一份")
	_expect(receiver.inventory.count_definition("low_grade_gel") == total, "由其他账号拾取时不重新计算倍率且不丢数量")
	_expect(receiver.inventory.count_definition("low_grade_energy_pack") == 1, "非目标物品不被加倍")
	var random := RandomNumberGenerator.new()
	random.seed = 42
	var baseline := server.reward_service.roll_monster_loot(monster, second.entity_id, random, int(Time.get_unix_time_from_system())).value as Array
	_expect(baseline.size() == 2 and baseline[0].quantity == 80, "第二账号击杀保持基础掉落")
	_expect(not server.handle_peer_loot_pickup(71, {"loot_id": spawned[0].loot_id, "multiplier": 999}).ok, "客户端拾取协议拒绝注入倍率")
	_test_probability()
	server.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	for failure: String in failures:
		push_error(failure)
	print("REWARD_AUTHORITY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 通过正式生产服务验证技能经验切面，并保持产品数量不变。
## [param server] 已注入统一奖励服务的服务器。
## [param source] 属于VIP账号的有效角色记录。
func _test_manufacturing(server: AuthoritativeServer, source: PlayerStateRecord) -> void:
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(source).value
	player.inventory.restore_items([])
	var book := ManufacturingRecipeBook.new()
	book.initialize(items)
	var recipe = book.recipe("material_upgrade_high_grade_density_solvent")
	_expect(recipe != null, "提炼配方存在")
	player.receive_loot(items.create(recipe.materials[0].definition_id, {"instance_id": "reward.fixture.input", "quantity": 5}).value)
	var state: PlayerStateRecord = mapper.to_record(player).value
	state.map_id = "glory_nft_bl_factory1"
	state.character_skills.refining = {"level": 150, "current_exp": 0, "fractional_exp": 0.0}
	var command := {"type": "start_production", "recipe_id": recipe.recipe_id, "station_id": "refining", "inventory_revision": state.inventory_revision, "multiplier": 999}
	var crafted: DomainResult = ProductionTestDriver.execute(server.manufacturing_service, state, command)
	_expect(crafted.is_ok, "生产事务成功")
	if not crafted.is_ok:
		return
	_expect(int(crafted.value.candidate.character_skills.refining.current_exp) == 100, "提炼40基础经验经VIP变为100")
	var next: Player = mapper.to_domain(crafted.value.candidate).value
	_expect(next.inventory.count_definition(recipe.product_definition_id) == 1, "经验倍率不增加生产物品")
	_expect(not ProductionTestDriver.execute(server.manufacturing_service, crafted.value.candidate, command).is_ok, "重复生产请求不重复发经验")


## 抽样验证任意非整数倍率的概率溢出和稀有物概率，不只放大已命中数量。
func _test_probability() -> void:
	var pipeline: RewardPipeline = RewardPolicyLoader.from_document({"schema_version": 1,
		"rules": [{"id": "fraction", "channel": "drop", "multiplier": 2.5}]}).value
	var context := RewardContext.new()
	context.channel = &"drop"
	var table := DropTable.new([
		{"item_definition_id": "a", "chance": 0.5, "minimum_quantity": 1, "maximum_quantity": 1},
		{"item_definition_id": "b", "chance": 0.01, "minimum_quantity": 1, "maximum_quantity": 1}])
	var random := RandomNumberGenerator.new()
	random.seed = 20260916
	var totals := {"a": 0, "b": 0}
	for _sample in range(20000):
		for drop: Dictionary in table.roll_with_modifiers(random, pipeline, context).value:
			totals[drop.item_definition_id] += int(drop.quantity)
	_expect(absf(float(totals.a) / 20000 - 1.25) < 0.02, "超过100%概率保留1.25数量期望")
	_expect(absf(float(totals.b) / 20000 - 0.025) < 0.005, "稀有物命中概率从1%提高到2.5%")
	var legacy := RandomNumberGenerator.new()
	legacy.seed = 77
	var neutral := RandomNumberGenerator.new()
	neutral.seed = 77
	for _sample in range(100):
		var a := table.roll(legacy)
		var b: Array = table.roll_with_modifiers(neutral, RewardPipeline.new(), context).value
		for row: Dictionary in b:
			row.erase("reward_settlement")
		_expect(a == b, "默认策略不改变掉落分布或随机序列")


## 记录权威链路断言。
## [param condition] 被检查的不变量。
## [param message] 失败时的定位信息。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
