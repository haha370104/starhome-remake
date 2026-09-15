extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
var failures: Array[String] = []
var assertions := 0
var catalog := ItemCatalog.new()


## 验证紫晶购买原子性、装置分组上限、旧存档迁移与双槽往返。
func _initialize() -> void:
	var fixture := Fixture.new()
	_expect(fixture.initialize().is_ok and catalog.initialize().is_ok, "夹具和物品目录初始化")
	var service := AuthoritativeCommerceService.new()
	_expect(service.initialize().is_ok, "商城初始化")
	var state := fixture._state
	var queried := service.execute(state, {"type": "query_premium_shop"})
	_expect(queried.is_ok and not queried.value.changed, "商城查询不写存档")
	var offers: Array = queried.value.panel_bundle.premium_shop.offers
	_expect(offers.size() == 16, "四种新式、五种旧式及七种升级材料，不含赠品")
	for offer: Dictionary in offers:
		if offer.family != "upgrade_material":
			_expect(int(offer.price) == (1000 if offer.family == "new_joint" else 2000), "装置本体沿用分代定价")
	var command := {"type": "buy_premium_item", "definition_id": offers[0].definition_id,
		"inventory_revision": state.inventory_revision, "price": 1, "amethyst": 999999, "quantity": 99}
	_expect(service.execute(state, command).error_code == &"commerce.insufficient_amethyst", "金币和伪造余额不能代替紫晶")
	state.amethyst = 5000
	var before := state.to_dictionary()
	var purchased := service.execute(state, command)
	_expect(purchased.is_ok, "充足紫晶购买成功")
	_expect(state.to_dictionary() == before, "执行事务不原地修改已提交存档")
	var candidate: PlayerStateRecord = purchased.value.candidate
	_expect(candidate.amethyst == 4000 and candidate.currency == state.currency, "忽略伪造价格和数量，仅扣一件紫晶")
	_expect(candidate.inventory_stacks.size() == state.inventory_stacks.size() + 1, "单件入包")
	_expect(service.execute(candidate, command).error_code == &"inventory.revision_conflict", "相同版本重放不得重复消费")
	command.definition_id = "recruit_tank"
	_expect(service.execute(state, command).error_code == &"commerce.item_not_offered", "禁止购买白名单外物品")
	command.definition_id = offers[0].definition_id
	state.inventory_capacity = state.inventory_stacks.size()
	var full := service.execute(state, command)
	_expect(not full.is_ok and state.amethyst == 5000, "背包满不扣款")
	state.inventory_capacity = 40
	var legacy := state.to_dictionary()
	legacy.erase("amethyst")
	_expect(PlayerStateRecord.from_dictionary(legacy).value.amethyst == 0, "旧存档缺字段默认零紫晶")
	legacy.amethyst = -1
	_expect(not PlayerStateRecord.from_dictionary(legacy).is_ok, "拒绝负余额")
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(state).value
	for source_class in ["HuoLiJieHeQi", "NewGunJoint", "gaoregun"]:
		var definition_id := _definition_for_class(source_class)
		var expected: Array = {"HuoLiJieHeQi": [16, 17], "NewGunJoint": [32, 33], "gaoregun": [14, 34]}[source_class]
		for index in range(3):
			var item: VehicleEquipment = catalog.create(definition_id, {
				"instance_id": "%s.%d" % [source_class, index], "quantity": 1, "upgrade_level": 2,
			}).value
			_expect(not item is VehicleWeapon, "接合器和发生器不会误分类为可开火主武器")
			_expect(player.receive_loot(item).is_ok, "装置进入背包")
			var result := player.equip_vehicle_item(item.instance_id, expected[0], player.inventory.revision, player.vehicle.loadout.revision)
			if index < 2:
				_expect(result.is_ok and player.vehicle.loadout.at(expected[index]) == item, "自动装入该类别的不同位置")
			else:
				_expect(result.error_code == &"equipment.attachment_slots_full" and player.inventory.find(item.instance_id) == item, "第三件被拒且仍留背包")
	var combat_catalog := CombatDefinitionCatalog.load_default()
	var movement := {"base_speed_multiplier": 1500.0, "base_speed_cap": 240.0}
	var baseline: DomainResult = combat_catalog.value.vehicle_combat_loadout(mapper.to_domain(state).value, 20, movement)
	var enhanced: DomainResult = combat_catalog.value.vehicle_combat_loadout(player, 20, movement)
	_expect(player.vehicle.loadout.attachment_bonus("energy_cannon_attack") == 104, "两件旧式与两件新式按各自强化值叠加")
	for ability: String in enhanced.value.weapons:
		if enhanced.value.weapons[ability].skill_id == "energy_cannon":
			_expect(enhanced.value.weapons[ability].minimum_damage == baseline.value.weapons[ability].minimum_damage + 104, "接合器进入实际伤害定义")
	player.vehicle.loadout.at(32).wear(99999)
	_expect(player.vehicle.loadout.attachment_bonus("energy_cannon_attack") == 92, "耐久归零不继续提供增益")
	var persisted := mapper.to_record(player)
	_expect(persisted.is_ok and persisted.value.amethyst == 5000, "装配不改变紫晶")
	var restored: Player = mapper.to_domain(persisted.value).value
	for location in [16, 17, 32, 33, 14, 34]:
		_expect(restored.vehicle.loadout.at(location) != null, "六件装置保存和重登后保留位置")
	_expect(restored.unequip_vehicle_item(33, restored.inventory.revision, restored.vehicle.loadout.revision).is_ok, "第二位置可卸装")
	var round_trip: Player = mapper.to_domain(mapper.to_record(restored).value).value
	_expect((round_trip.inventory.find("NewGunJoint.1") as Equipment).upgrade_level == 2, "卸装后强化等级经存档仍保留")
	var current := CurrentPlayer.new(catalog)
	var projected := PlayerPanelProjector.new(catalog).build_bundle(player)
	_expect(current.apply_bundle(projected), "客户端接受六装置快照")
	_expect(current.vehicle.loadout.at(33) != null and current.amethyst.balance() == 5000, "客户端还原实际第二槽和紫晶")
	# 模拟旧版只有两个新式接合器占用 16/17 的存档。
	var migrated_state := fixture._state.duplicate_record()
	for location in [32, 33]:
		for slot: EquipmentSlotRecord in persisted.value.equipment_slots:
			if slot.slot_location == location:
				var old_slot := slot.duplicate_record()
				old_slot.slot_location = 16 if location == 32 else 17
				migrated_state.equipment_slots.append(old_slot)
	var migrated := mapper.to_domain(migrated_state)
	_expect(migrated.is_ok and migrated.value.vehicle.loadout.at(33) != null, "旧新式装配自动迁移，不丢第二件")
	_finish()


## 在测试边界用溯源类名定位具体配置，运行时交易仍只用稳定 ID。
## [param source_class] 原版类名。
## 返回匹配定义标识。
func _definition_for_class(source_class: String) -> String:
	for definition_id: String in catalog.definition_ids():
		if catalog.definition(definition_id).get("source_class", "") == source_class:
			return definition_id
	return ""


## 记录行为断言。
## [param condition] 验证条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出结果并结束隔离测试进程。
func _finish() -> void:
	if failures.is_empty():
		print("PREMIUM_ATTACHMENTS_OK (%d assertions)" % assertions)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)
