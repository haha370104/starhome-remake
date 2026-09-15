extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
var items := ItemCatalog.new()
var fixture := Fixture.new()
var service := AuthoritativeCommerceService.new()
var mapper: PlayerStateMapper
var checks := 0
var failures: Array[String] = []


## 等待内容包挂载后测试真实强化交易。
func _initialize() -> void:
	call_deferred("_run")


## 对九种接合器全部40阶段验证材料金币、属性、实例身份、装配与存档。
func _run() -> void:
	_expect(items.initialize().is_ok and fixture.initialize().is_ok and service.initialize().is_ok, "服务初始化")
	mapper = PlayerStateMapper.new(items)
	var pricing := PremiumShopService.new()
	pricing.initialize(items)
	var rules: Array = JsonConfigLoader.load_dictionary("res://data/gameplay/commerce/attachment_upgrade_costs_v1.json").value.rules
	for rule: Dictionary in rules:
		var plan := pricing.upgrade_pricing().plan_for(rule.attachment_id, int(rule.current_level))
		for installed: bool in [false, true]:
			var player := _funded(plan, installed)
			var equipment := player.attachment_item("upgrade-target")
			var original_view := equipment.to_view_dictionary()
			var state: PlayerStateRecord = mapper.to_record(player).value
			var before := state.to_dictionary()
			var command := {"type": "upgrade_attachment", "instance_id": equipment.instance_id,
				"inventory_revision": state.inventory_revision, "loadout_revision": state.vehicle_loadout_revision,
				"target_level": 99, "currency": 0, "materials": [], "reward": 999999}
			var result := service.execute(state, command)
			_expect(result.is_ok and state.to_dictionary() == before, "强化只生成隔离候选，不修改原存档")
			if not result.is_ok:
				continue
			var next: PlayerStateRecord = result.value.candidate
			var updated: Player = mapper.to_domain(next).value
			var upgraded := updated.attachment_item("upgrade-target")
			_expect(upgraded.upgrade_level == plan.target_level and next.currency == 0 and next.amethyst == state.amethyst, "恰升一级、精确扣金币、不重复扣紫晶")
			_expect(upgraded.instance_id == equipment.instance_id and upgraded.durability == original_view.durability
				and upgraded.max_durability == original_view.max_durability and upgraded.bound == equipment.bound
				and upgraded.equipment_location == equipment.equipment_location, "耐久、身份、绑定及槽位保持 %s installed=%s bound=%s/%s location=%s/%s" % [plan.definition_id, installed, upgraded.bound, equipment.bound, upgraded.equipment_location, equipment.equipment_location])
			_expect(next.inventory_revision == state.inventory_revision + 1
				and next.vehicle_loadout_revision == state.vehicle_loadout_revision + (1 if installed else 0), "只推进涉及的领域版本")
			for requirement: Dictionary in plan.requirements:
				_expect(updated.inventory.count_consumable_definition(requirement.definition_id) == 0, "精确消耗该阶段全部材料")
			var effect := String(upgraded.stat("attachment_effect"))
			var values: Array = upgraded.stat("attachment_values")
			_expect(upgraded.attachment_bonus(effect) == int(values[plan.target_level]), "升级效果读取当前档数值")
			if installed:
				_expect(updated.vehicle.loadout.attachment_bonus(effect) >= int(values[plan.target_level]), "已装配加值立即进入战车装配模型")
				if effect == "energy_cannon_attack":
					var combat := CombatDefinitionCatalog.load_default()
					var movement := {"base_speed_multiplier": 1500.0, "base_speed_cap": 240.0}
					var old_loadout: Dictionary = combat.value.vehicle_combat_loadout(player, 20, movement).value
					var new_loadout: Dictionary = combat.value.vehicle_combat_loadout(updated, 20, movement).value
					_expect(new_loadout.weapons["energy_cannon.primary"].minimum_damage - old_loadout.weapons["energy_cannon.primary"].minimum_damage
						== int(values[plan.target_level]) - int(values[plan.current_level]), "强化增加真实权威能量炮伤害")
			var restored := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(next.to_dictionary())))
			_expect(restored.is_ok and mapper.to_domain(restored.value).value.attachment_item("upgrade-target").upgrade_level == plan.target_level
				and not service.execute(restored.value, command).is_ok, "JSON重启保留强化且旧请求不可重放")
			_expect(not service.execute(state, {"type": "upgrade_attachment", "instance_id": "other-player-item",
				"inventory_revision": state.inventory_revision, "loadout_revision": state.vehicle_loadout_revision}).is_ok, "不能强化不属于自己的实例")
	var first: Dictionary = rules[0]
	var first_plan := pricing.upgrade_pricing().plan_for(first.attachment_id, 0)
	for failure: String in ["locked_equipment", "locked_material", "missing_material", "stale_inventory", "stale_loadout", "max_level"]:
		var player := _funded(first_plan, false)
		if failure == "locked_equipment":
			player.attachment_item("upgrade-target").locked = true
		elif failure == "locked_material":
			player.inventory.items()[1].locked = true
		elif failure == "missing_material":
			player.inventory.consume_definition(first_plan.requirements[0].definition_id, 1)
		elif failure == "max_level":
			player.attachment_item("upgrade-target").upgrade_level = 5
		var state: PlayerStateRecord = mapper.to_record(player).value
		var before := state.to_dictionary()
		var result := service.execute(state, {"type": "upgrade_attachment", "instance_id": "upgrade-target",
			"inventory_revision": state.inventory_revision - (1 if failure == "stale_inventory" else 0),
			"loadout_revision": state.vehicle_loadout_revision - (1 if failure == "stale_loadout" else 0)})
		_expect(not result.is_ok and state.to_dictionary() == before, "拒绝且完全不修改状态：" + failure)
	var old: Dictionary = rules[20]
	var locked_player := _funded(first_plan, true)
	locked_player.attachment_item("upgrade-target").locked = true
	var locked_state: PlayerStateRecord = mapper.to_record(locked_player).value
	_expect(not service.execute(locked_state, {"type": "upgrade_attachment", "instance_id": "upgrade-target",
		"inventory_revision": locked_state.inventory_revision, "loadout_revision": locked_state.vehicle_loadout_revision}).is_ok
		and mapper.to_domain(locked_state).value.attachment_item("upgrade-target").locked, "已装配锁定标记保存后仍阻止强化")
	var old_plan := pricing.upgrade_pricing().plan_for(old.attachment_id, int(old.current_level))
	var poor := _funded(old_plan, true)
	poor.inventory.currency = old_plan.currency - 1
	var before: Dictionary = mapper.to_record(poor).value.to_dictionary()
	_expect(not poor.upgrade_attachment("upgrade-target", old_plan, poor.inventory.revision, poor.vehicle.loadout.revision).is_ok
		and mapper.to_record(poor).value.to_dictionary() == before, "直接领域调用金币不足也不扣材料")
	for failure: String in failures:
		push_error(failure)
	print("ATTACHMENT_UPGRADE checks=%d failures=%d stages=%d" % [checks, failures.size(), rules.size()])
	quit(0 if failures.is_empty() else 1)


## 按真实配方给夹具精确数量材料，保留底盘及原装备，支持测试装配状态。
## [param plan] 当前阶段材料规则。
## [param installed] 目标是否装在战车上。
## 返回可直接强化的玩家聚合。
func _funded(plan: AttachmentUpgradePlan, installed: bool) -> Player:
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory.restore_items([])
	player.inventory.currency = plan.currency
	var equipment: VehicleEquipment = items.create(plan.definition_id, {"instance_id": "upgrade-target", "upgrade_level": plan.current_level,
		"durability": 1, "bound": true}).value
	player.receive_loot(equipment)
	if installed:
		_expect(player.equip_vehicle_item(equipment.instance_id, equipment.equipment_location, player.inventory.revision, player.vehicle.loadout.revision).is_ok, "目标装配成功")
	for requirement: Dictionary in plan.requirements:
		var remaining := int(requirement.quantity)
		while remaining > 0:
			var amount := mini(remaining, int(items.definition(requirement.definition_id).get("max_stack", 1)))
			var received := player.receive_loot(items.create(requirement.definition_id, {"instance_id": "%s.%d" % [requirement.definition_id, remaining], "quantity": amount}).value)
			_expect(received.is_ok, "实际背包可容纳配方材料 %s %s %s" % [plan.definition_id, requirement.definition_id, received.error_message])
			remaining -= amount
	return player


## 汇总服务与领域行为断言。
## [param condition] 必须成立的条件。
## [param message] 失败时定位信息。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
