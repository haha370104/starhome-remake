extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证所有发生器常驻属性在装配、客户端投影、运行期副本和真实JSON保存中一致。
func _initialize() -> void:
	var catalog := ItemCatalog.new()
	_check(catalog.initialize().is_ok, "目录")
	var fixture := PlayerPanelServiceFixture.new()
	_check(fixture.initialize().is_ok, "隔离存档夹具")
	var mapper := PlayerStateMapper.new(catalog)
	var combat: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	for id: String in catalog.generator_rules.profiles:
		var player: Player = mapper.to_domain(fixture._state).value
		var base := player.calculate_vehicle_stats()
		var created := catalog.create(id, {"instance_id": "generator.test"})
		_check(created.is_ok, "实例：" + id)
		if not created.is_ok: continue
		var equipment: VehicleEquipment = created.value
		var profile := equipment.generator_profile
		_check(profile != null and equipment.allowed_locations == [14, 34], "两处固定槽")
		_check(player.vehicle.loadout.equip(equipment, 14, player.vehicle.loadout.revision).is_ok, "安装")
		player.vehicle.reconcile_loadout_state(false)
		var stats := player.calculate_vehicle_stats()
		_check(stats.max_health == base.max_health + profile.max_health and stats.defense == base.defense + profile.defense, "面板生命防御")
		_check(stats.energy_cannon_attack == base.energy_cannon_attack + profile.energy_cannon_attack, "面板能量炮攻击")
		var loadout := combat.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240})
		_check(loadout.is_ok, "权威装配")
		_check(loadout.value.assembly.max_health == stats.max_health and loadout.value.assembly.defense == stats.defense, "实际战斗生命防御")
		_check(loadout.value.weapons["energy_cannon.primary"].minimum_damage == stats.energy_cannon_attack, "面板与实际攻击一致")
		var condition := EquipmentConditionLoadout.new(player).duplicate_loadout()
		_check(condition.generators().size() == 1 and condition.generators()[0] != equipment, "独立运行实例")
		_check(condition.generators()[0].generator_profile == profile, "复用只读配置")
		if equipment.ammunition_capacity() > 0:
			condition.accept_shot(equipment.instance_id)
			_check(condition.generators()[0].magazine.remaining == equipment.magazine.remaining - 1, "弹药副本独立")
			equipment.magazine.consume()
		var record: PlayerStateRecord = mapper.to_record(player).value
		var encoded: Dictionary = JSON.parse_string(JSON.stringify(record.to_dictionary()))
		var decoded := PlayerStateRecord.from_dictionary(encoded)
		_check(decoded.is_ok, "真实JSON重读")
		var restored: Player = mapper.to_domain(decoded.value).value
		_check(restored.vehicle.loadout.at(14).magazine.remaining == equipment.magazine.remaining, "余弹保存")
		_check(restored.calculate_vehicle_stats() == stats, "重启不重复常驻增益")
		_check("generator_effects" in equipment.to_view_dictionary(), "详情显示能力与边界")
		equipment.durability = 0
		player.vehicle.reconcile_loadout_state(false)
		var broken := player.calculate_vehicle_stats()
		_check(broken.max_health == base.max_health and broken.defense == base.defense and broken.energy_cannon_attack == base.energy_cannon_attack, "损坏不提供属性")
	print("Generator loadout: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总断言，不接触用户实际存档。
## [param condition] 实际条件。
## [param label] 失败说明。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
