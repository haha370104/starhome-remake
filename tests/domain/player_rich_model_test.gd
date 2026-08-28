extends SceneTree

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const CurrentPlayerScript := preload("res://scripts/client/state/current_player.gd")
const PlayerPanelProjectorScript := preload(
	"res://scripts/server/player_panels/player_panel_projector.gd"
)
const EquipmentSlotRegistryScript := preload(
	"res://scripts/domain/equipment/equipment_slot_registry.gd"
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
	var bundle := PlayerPanelProjectorScript.new(catalog).build_bundle(player)
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
