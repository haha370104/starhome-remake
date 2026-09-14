extends SceneTree

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const CurrentPlayerScript := preload("res://scripts/client/state/current_player.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/shared/player_panel_projector.gd"
)
const EquipmentSlotRegistryScript := preload(
	"res://scripts/domain/equipment/equipment_slot_registry.gd"
)
const CombatDefinitionCatalogScript := preload(
	"res://scripts/domain/combat/combat_definition_catalog.gd"
)

var failures: PackedStringArray = []
var assertions := 0


## 验证具体物品类型、固定装备槽、原子换装和客户端共享 Player 重建。
func _initialize() -> void:
	var catalog: ItemCatalog = ItemCatalogScript.new()
	var initialized := catalog.initialize()
	_expect(initialized.is_ok, "物品目录应完成初始化")
	if not initialized.is_ok:
		_finish()
		return
	_expect(catalog.definition_ids().size() == 1290, "14项基础物品、6项官网火箭炮与1270项荣耀物品应全部可实例化")
	var glory_chassis_id := "glory_equipment_tank1_c2ba1ac5af"
	var glory_chassis_definition := catalog.definition(glory_chassis_id)
	_expect(not glory_chassis_definition.is_empty(), "新兵战车源定义应进入统一物品目录")
	if not glory_chassis_definition.is_empty():
		var glory_chassis := catalog.create(glory_chassis_id, {"instance_id": "glory.chassis"})
		_expect(glory_chassis.is_ok and glory_chassis.value is VehicleChassis, "荣耀战车应组装为充血底盘类型")
	var player := _build_player(catalog)
	_expect(player != null, "测试玩家聚合应完成组装")
	if player == null:
		_finish()
		return
	var shirt := player.inventory.find("item.shirt")
	_expect(shirt is Clothing, "无袖衫应组装为 Clothing，而非通用字典")
	var worn := player.equip_character_item("item.shirt", "upper_body", 0, 0)
	_expect(worn.is_ok, "Player 应完成服装原子换装")
	_expect(player.character_equipment.at("upper_body") == shirt, "人物槽应持有背包中同一个服装实例")
	_expect(player.inventory.find("item.shirt") == null, "已穿服装不应继续留在背包")
	var wrong_slot := catalog.create("male_sleeveless_shirt", {
		"instance_id": "item.invalid_shirt", "footprint_px": [45, 45],
	})
	_expect(wrong_slot.is_ok, "第二件服装应完成类型构造")
	var inserted := player.inventory.add_from_transfer(wrong_slot.value)
	_expect(inserted.is_ok, "第二件服装应放入背包")
	var item_count_before := player.inventory.items().size()
	var rejected := player.equip_character_item(
		"item.invalid_shirt", "head", player.inventory.revision, player.revision
	)
	_expect(not rejected.is_ok, "服装安装到错误槽位必须被拒绝")
	_expect(player.inventory.items().size() == item_count_before, "失败换装不得改变背包")
	_expect(player.inventory.find("item.invalid_shirt") != null, "失败换装不得吞掉物品")
	var stats := player.vehicle.calculate_stats()
	_expect(stats.defense == 10, "战车防御应由底盘对象计算为 10")
	_expect(stats.energy_cannon_attack == 7, "主武器对象应提供 7 点能量炮攻击")
	_expect(stats.self_repair_base == 5, "底盘对象应提供 5 点基础自维修力")
	_expect(stats.self_repair_total == 5, "维修技能等级不应直接放大战车自维修力")
	_expect(stats.required_repair_skill_level == 10, "底盘应保存 10 级维修技能使用门槛")
	_expect(is_equal_approx(stats.self_repair_energy_cost, 5.0), "底盘应保存单周期 5 点维修能耗")
	var chassis := player.vehicle.loadout.at(0) as VehicleChassis
	_expect(chassis.can_activate_self_repair(10), "达到底盘维修门槛时应允许启动自维修")
	_expect(not chassis.can_activate_self_repair(9), "低于底盘维修门槛时应拒绝启动自维修")
	_test_advanced_vehicle_loadout(catalog, player)
	var bundle := PlayerPanelProjectorScript.new(catalog).build_bundle(player)
	var advanced_chassis := _equipped_view(bundle.vehicle.equipped, 0)
	var advanced_weapon := _equipped_view(bundle.vehicle.equipped, 1)
	_expect(advanced_chassis.dialog_anchor == [170, 200],
		"撒玛王底盘应复用 Location 0 的原客户端业务锚点")
	_expect(advanced_weapon.dialog_anchor == [170, 200],
		"天神之怒应复用 Location 1 的原客户端业务锚点")
	var current: CurrentPlayer = CurrentPlayerScript.new()
	_expect(current.apply_bundle(bundle), "客户端应从网络 DTO 重建 CurrentPlayer")
	_expect(current is Player, "客户端全局自己应当就是 Player 子类")
	_expect(current.character_equipment.at("upper_body") is Clothing, "客户端人物面板与场景应共享同一服装对象")
	_expect(current.vehicle.loadout.at(1) is VehicleWeapon, "客户端战车槽应恢复具体武器类型")
	_expect(EquipmentSlotRegistryScript.display_slot_id(19) == 10 \
		and EquipmentSlotRegistryScript.display_slot_id(24) == 10 \
		and EquipmentSlotRegistryScript.display_slot_id(28) == 10,
		"三系特殊装备第一个逻辑槽应映射到同一视觉行")
	_expect(EquipmentSlotRegistryScript.special_series(22) == "sama" \
		and EquipmentSlotRegistryScript.special_row(31) == 3,
		"充血装配模型应保留特殊装备系列与四行语义")
	_expect(EquipmentSlotRegistryScript.display_name(18) == "宏原子",
		"Location 18 应恢复为荣耀版宏原子槽")
	_expect(
		EquipmentSlotRegistryScript.location_for_definition("starter_rocket_launcher") == 13
		and EquipmentSlotRegistryScript.location_for_definition("starter_missile") == 13,
		"火箭炮与导弹必须竞争同一个 Location 13 战术槽",
	)
	var first_loot := catalog.create("low_grade_gel", {
		"instance_id": "loot.first", "quantity": 2, "footprint_px": [30, 30],
	})
	var second_loot := catalog.create("low_grade_gel", {
		"instance_id": "loot.second", "quantity": 3, "footprint_px": [30, 30],
	})
	_expect(first_loot.is_ok and second_loot.is_ok, "怪物材料应由物品目录组装为可堆叠物品")
	_expect(player.receive_loot(first_loot.value).is_ok, "首次掉落应进入背包空位")
	_expect(player.receive_loot(second_loot.value).is_ok, "同定义掉落应合并到已有堆叠")
	_expect(player.inventory.find("loot.first").quantity == 5, "合并后的掉落数量应为权威结算总和")
	_expect(player.inventory.find("loot.second") == null, "已合并掉落不应额外占用背包格")
	_finish()


## 从权威装备快照中查找指定 Location 的视图。
## [param equipped] `PlayerPanelProjector` 输出的装备视图数组。
## [param location] 需要查找的旧客户端固定槽编号。
## 返回匹配的装备视图；不存在时返回空字典。
func _equipped_view(equipped: Array, location: int) -> Dictionary:
	for value: Variant in equipped:
		if value is Dictionary and int((value as Dictionary).get("location", -1)) == location:
			return value
	return {}


## 验证撒玛王底盘与天神之怒从同一装配对象派生身份、面板及权威战斗数值。
## [param catalog] 已初始化的统一物品目录。
## [param player] 已装配新兵战车的测试玩家聚合。
func _test_advanced_vehicle_loadout(catalog: ItemCatalog, player: Player) -> void:
	var chassis_id := "glory_equipment_tank1000_27ae5e8059"
	var weapon_id := "glory_equipment_gun1000_c4c24e2500"
	for specification: Dictionary in [
		{"id": chassis_id, "instance": "item.sama_chassis", "position": [120, 0]},
		{"id": weapon_id, "instance": "item.divine_weapon", "position": [180, 0]},
	]:
		var created := catalog.create(String(specification.id), {
			"instance_id": specification.instance,
			"position_px": specification.position,
			"footprint_px": [45, 45],
		})
		_expect(created.is_ok, "高级战车装备应从荣耀目录组装")
		if created.is_ok:
			_expect(player.inventory.add_from_transfer(created.value).is_ok, "高级装备应进入同一玩家背包")
	var chassis_equipped := player.equip_vehicle_item(
		"item.sama_chassis", 0, player.inventory.revision, player.vehicle.loadout.revision
	)
	_expect(chassis_equipped.is_ok, "撒玛王战车应替换 Location 0 底盘")
	var weapon_equipped := player.equip_vehicle_item(
		"item.divine_weapon", 1, player.inventory.revision, player.vehicle.loadout.revision
	)
	_expect(weapon_equipped.is_ok, "天神之怒应替换 Location 1 主炮")
	var stats := player.calculate_vehicle_stats()
	_expect(player.vehicle.definition_id == chassis_id, "战车身份必须由实际底盘装配同步")
	_expect(stats.max_health == 13000, "撒玛王战车最大生命应为 13000")
	_expect(stats.energy_cannon_attack == 900, "天神之怒基础攻击应为 900")
	_expect(stats.working_energy_capacity == 10000.0, "荣耀旧字段应提升为一万工作能量上限")
	_expect(stats.reserve_energy_capacity == 100000.0, "荣耀旧字段应提升为十万储备能量上限")
	var combat_catalog_result := CombatDefinitionCatalogScript.load_default()
	_expect(combat_catalog_result.is_ok, "权威战斗目录应完成初始化")
	if not combat_catalog_result.is_ok:
		return
	var combat_loadout: DomainResult = combat_catalog_result.value.vehicle_combat_loadout(
		player,
		20,
		{"base_speed_multiplier": 1500.0, "base_speed_cap": 240.0},
	)
	_expect(combat_loadout.is_ok, "权威战斗装配应直接消费当前 Player loadout")
	if combat_loadout.is_ok:
		_expect(combat_loadout.value.assembly.max_health == 13000,
			"权威战斗生命不得回退到新兵底盘")
		_expect(combat_loadout.value.weapons["energy_cannon.primary"].minimum_damage == 900,
			"权威命中伤害不得回退到新兵能量炮")


## 创建包含背包、固定人物装备和固定战车装配的测试玩家。
## [param catalog] 已初始化物品目录。
## 返回组装成功的 Player；任一目录错误时返回 null。
func _build_player(catalog: ItemCatalog) -> Player:
	var player := Player.new({
		"character_id": "character.test",
		"display_name": "测试玩家",
		"sex": "male",
		"revision": 0,
		"inventory_revision": 0,
		"inventory_capacity": 40,
		"vehicle": {
			"vehicle_id": "vehicle.test",
			"definition_id": "recruit_tank",
			"loadout_revision": 0,
			"max_health": 70,
			"health": 70,
			"reserve_energy_capacity": 10000,
			"reserve_energy": 10000,
			"working_energy_capacity": 100,
			"working_energy": 100,
			"output_power": 21,
		},
	})
	var shirt := catalog.create("male_sleeveless_shirt", {
		"instance_id": "item.shirt",
		"position_px": [0, 0],
		"footprint_px": [45, 45],
	})
	if not shirt.is_ok or not player.inventory.restore_items([shirt.value]).is_ok:
		return null
	for definition_id: String in ["recruit_tank", "beginner_engine", "recruit_energy_cannon"]:
		var equipment := catalog.create(definition_id, {
			"instance_id": "equipped.%s" % definition_id,
			"footprint_px": [45, 45],
		})
		if not equipment.is_ok or not player.vehicle.loadout.restore(equipment.value).is_ok:
			return null
	return player


## 汇总断言并退出独立测试进程。
func _finish() -> void:
	if failures.is_empty():
		print("PLAYER_RICH_MODEL_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 记录一个布尔断言。
## [param condition] 预期成立的条件。
## [param message] 失败时输出的信息。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
