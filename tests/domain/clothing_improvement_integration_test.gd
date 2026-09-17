extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证改良与原创宝石共存、服务端战斗和客户端一致、保存及磨损副本保留规则。
func _initialize() -> void:
	var items := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	_check(items.initialize().is_ok and fixture.initialize().is_ok, "目录初始化")
	var mapper := PlayerStateMapper.new(items)
	var combat: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var rules := items.clothing_improvement_rules
	var id := ""
	for candidate: String in rules.slots:
		if items.definition(candidate).required_sex == "male" and rules.slots[candidate] == "upper_body":
			id = candidate
			break
	_check(not id.is_empty(), "可穿季节上衣")
	for channel: ClothingImprovementRules.Channel in rules.channels.values():
		var player: Player = mapper.to_domain(fixture._state).value
		var before := player.calculate_vehicle_stats()
		var improved: Clothing = items.create(id, {"instance_id": "improved", "clothing_improvement": {"attribute": channel.attribute, "level": 10}}).value
		_check(player.inventory.add_reward(improved).is_ok, "改良时装入包")
		var bag: Player = mapper.to_domain(mapper.to_record(player).value).value
		_check(bag.inventory.find("improved").improvement.level == 10, "背包保存成长")
		_check(player.equip_character_item("improved", "upper_body", player.inventory.revision, player.revision).is_ok, "装配时装")
		var actual := player.calculate_vehicle_stats()
		var loadout: Dictionary = combat.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240}).value
		_check(actual.max_health == loadout.assembly.max_health, "生命面板战斗一致")
		_check(is_equal_approx(actual.speed, loadout.assembly.movement_speed), "速度面板战斗一致")
		_check(actual.energy_cannon_attack == loadout.weapons["energy_cannon.primary"].minimum_damage, "炮伤面板战斗一致")
		var stat_key: String = {"movement_speed": "speed", "self_repair": "self_repair_bonus"}.get(channel.attribute, channel.attribute)
		if channel.attribute not in ["missile_attack", "rocket_attack"]:
			_check(is_equal_approx(actual[stat_key] - before[stat_key], channel.increment * 10), "战车实际收益 " + channel.attribute)
		_check(player.vehicle.health == 70, "提高上限不治疗")
		var persisted := mapper.to_record(player)
		_check(persisted.is_ok, "装备存档")
		var restored: Player = mapper.to_domain(PlayerStateRecord.from_dictionary(persisted.value.to_dictionary()).value).value
		_check(restored.calculate_vehicle_stats() == actual, "重启不重复加成")
		var current := CurrentPlayer.new(items)
		_check(current.apply_bundle(fixture._service.build_bundle(persisted.value)), "客户端快照恢复")
		_check(current.character_equipment.at("upper_body").improvement.level == 10 and current.calculate_vehicle_stats() == actual, "客户端保留成长和派生属性")
		var copied := EquipmentConditionLoadout.new(player).duplicate_loadout()
		var copy: Clothing = copied._items["improved"]
		_check(copy.improvement_rules == rules and copy.improvement.level == 10, "磨损副本保留规则")
		copy.improvement.level = 20
		_check(improved.improvement.level == 10, "副本成长隔离")
		var enhancement_rules: ClothingEnhancementRules = ClothingEnhancementRules.load_default().value
		var clothes: Array[Clothing] = []
		for n in range(3):
			var piece: Clothing = items.create(id, {"instance_id": str(n), "clothing_improvement": {"attribute": channel.attribute, "level": 10}}).value
			piece.enhancement.gem = channel.attribute
			piece.enhancement.gem_stage = 7
			clothes.append(piece)
		var sum := ClothingBonuses.collect(clothes, enhancement_rules)
		var expected := channel.increment * 30 + enhancement_rules.gem_increment(channel.attribute) * 14
		_check(is_equal_approx(sum.apply_value(channel.attribute, 0), expected), "三件原版改良加两件宝石")
		clothes[2].durability = 0
		_check(is_equal_approx(ClothingBonuses.collect(clothes, enhancement_rules).apply_value(channel.attribute, 0), expected - channel.increment * 10), "损坏时装禁用改良")
	print("Clothing improvement integration: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计与具体行为关联的断言。
## [param condition] 期望成立的行为。
## [param label] 失败说明。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
