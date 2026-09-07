extends SceneTree

const PanelFixtureScript := preload("res://tests/fixtures/player_panel_service_fixture.gd")

var failures: PackedStringArray = []
var assertions := 0


## 验证三面板查询、像素移动、revision 冲突和原子换装。
func _initialize() -> void:
	var authority = PanelFixtureScript.new()
	var initialized := authority.initialize()
	_expect(initialized.is_ok, "离线权威夹具应完成初始化")
	if not initialized.is_ok:
		_finish()
		return
	var queried := authority.execute({"type": "query"})
	_expect(queried.is_ok, "面板查询应返回权威快照")
	var bundle: Dictionary = queried.value
	_expect(bundle.has("character") and bundle.has("inventory") and bundle.has("vehicle"), "查询必须成组返回三面板")
	_expect(bundle.inventory.items.size() == 2, "初始背包应包含引擎和训练服")
	_expect(bundle.vehicle.equipped.size() == 3, "初始战车应包含底盘、主武器和引擎")
	_expect(bundle.character.skills.size() == 13, "人物快照应包含首版启用的十三项技能")
	_expect(bundle.character.level == 10, "新角色综合等级应从十级起算")
	_expect(bundle.character.skills[0].next_level_experience == 181,
		"技能快照应由成长配置投影十级能量炮门槛")
	_expect(bundle.vehicle.stats.weight == 140, "整车重量应由底盘、引擎和主武器聚合为 140")
	_expect(bundle.vehicle.stats.defense == 10, "整车防御应读取新兵战车基础防御 10")
	_expect(bundle.vehicle.stats.armor_front == 0 and bundle.vehicle.stats.armor_rear == 0 \
			and bundle.vehicle.stats.armor_left == 0 and bundle.vehicle.stats.armor_right == 0,
		"未安装四向护甲时不能把底盘防御重复投影到护甲槽")
	_expect(bundle.vehicle.stats.energy_cannon_attack == 7, "新兵能量炮攻击应为目录值 7")
	var chassis: Dictionary = bundle.vehicle.equipped[0]
	_expect(chassis.dialog_anchor == [170, 200], "底盘对话框锚点应来自旧客户端 EquipInDlg")
	_expect(chassis.stats.max_health == 70, "装备悬浮快照应携带服务端目录属性")
	_expect(chassis.slot_id == "chassis" and chassis.display_slot_id == -1,
		"投影器应从领域槽位注册表输出中央底盘语义")

	var inventory_revision := int(bundle.inventory.revision)
	var moved := authority.execute({
		"type": "move_inventory_item",
		"instance_id": "inventory.spare_engine",
		"position_px": [92, 61],
		"inventory_revision": inventory_revision,
	})
	_expect(moved.is_ok, "合法像素移动应成功")
	if moved.is_ok:
		bundle = moved.value
		_expect(bundle.inventory.items[0].position_px == [90, 60], "服务器应按 15 像素网格吸附")
	var stale := authority.execute({
		"type": "move_inventory_item",
		"instance_id": "inventory.spare_engine",
		"position_px": [0, 0],
		"inventory_revision": inventory_revision,
	})
	_expect(not stale.is_ok and stale.error_code == &"inventory.revision_conflict", "过期背包 revision 必须被拒绝")

	var before_transaction := bundle.duplicate(true)
	var equipped := authority.execute({
		"type": "equip_vehicle_item",
		"instance_id": "inventory.spare_engine",
		"location": 3,
		"inventory_revision": int(bundle.inventory.revision),
		"loadout_revision": int(bundle.vehicle.revision),
	})
	_expect(equipped.is_ok, "双 revision 正确时应原子替换引擎")
	if equipped.is_ok:
		bundle = equipped.value
		_expect(bundle.inventory.items.size() == 2, "被替换引擎应在同一事务回到背包且保留训练服")
		_expect(bundle.vehicle.equipped.size() == 3, "换装后战车槽位数应保持一致")
		_expect(bundle.transaction_revision > before_transaction.transaction_revision, "换装应推进聚合事务 revision")
	var character_equipped := authority.execute({
		"type": "equip_character_item",
		"instance_id": "inventory.training_shirt",
		"character_slot": "upper_body",
		"inventory_revision": int(bundle.inventory.revision),
		"state_revision": int(bundle.transaction_revision),
	})
	_expect(character_equipped.is_ok, "人物服装应由服务器校验性别和槽位后穿上")
	if character_equipped.is_ok:
		bundle = character_equipped.value
		_expect(bundle.character.worn_items.size() == 1, "人物面板应收到独立 dialog 穿着层")
	var loot_grant := authority.grant_loot({
		"loot_id": "monster.loot.1",
		"item_definition_id": "low_grade_biosilicon",
		"quantity": 3,
	})
	_expect(loot_grant.is_ok, "权威掉落应通过同一玩家聚合进入背包")
	if loot_grant.is_ok:
		var loot_items: Array = loot_grant.value.inventory.items
		var matches := loot_items.filter(func(item: Dictionary) -> bool:
			return String(item.get("definition_id", "")) == "low_grade_biosilicon" \
				and int(item.get("amount", 0)) == 3
		)
		_expect(matches.size() == 1, "面板快照应立即包含权威结算的三份低级生物硅")
		if not matches.is_empty():
			_expect(String(matches[0].get("icon", "")).ends_with("/inventory_icon.png"),
				"材料领域物品的背包投影应选择 inventory 表现")
	var damage_progress := authority.grant_skill_progression({
		"entity_id": "player.local",
		"source": "effective_damage",
		"skill_id": "energy_cannon",
		"damage": 7,
	})
	_expect(damage_progress.is_ok, "最终有效能量炮伤害应产生对应技能经验")
	if damage_progress.is_ok:
		var damage_bundle: Dictionary = damage_progress.value.panel_bundle
		_expect(damage_bundle.character.skills[0].experience == 7,
			"七点最终有效伤害应按默认倍率产生七点经验")
		_expect(damage_progress.value.progression.visible_progress_changed \
				and damage_progress.value.progression.progress_percent == 3,
			"能量炮命中跨越可见百分点时应触发面板刷新")
	var driving_progress := authority.grant_skill_progression({
		"entity_id": "player.local",
		"source": "accepted_driving_movement",
		"skill_id": "driving",
		"distance": 1000.0,
		"vehicle_weight": 140.0,
	})
	_expect(driving_progress.is_ok, "碰撞校验后的驾驶距离应按整车重量换算经验")
	if driving_progress.is_ok:
		var driving_skill: Dictionary = driving_progress.value.panel_bundle.character.skills[2]
		_expect(driving_skill.experience == 14, "驾驶经验提速十倍后，一千像素乘 140 重量应形成十四点经验")
		_expect(absf(float(driving_skill.fractional_experience)) < 0.0001,
			"整除后的驾驶经验不应留下小数余量")
	var upgraded := authority.grant_skill_progression({
		"entity_id": "player.local",
		"source": "authoritative_action",
		"skill_id": "energy_cannon",
		"amount": 174.0,
	})
	_expect(upgraded.is_ok and bool(upgraded.value.progression.upgraded),
		"达到门槛的单次服务端发放应只提升一级")
	if upgraded.is_ok:
		_expect(upgraded.value.panel_bundle.character.skills[0].base_level == 11 \
			and upgraded.value.panel_bundle.character.skills[0].experience == 0,
			"升级后当前经验与溢出应归零")
		_expect(upgraded.value.panel_bundle.character.level == 10,
			"单个半权重技能提升一级时综合等级仍应向下取整为十")

	var spare_chassis := authority.grant_loot({
		"loot_id": "inventory.spare_chassis",
		"item_definition_id": "glory_equipment_tank1_c2ba1ac5af",
		"quantity": 1,
	})
	_expect(spare_chassis.is_ok, "测试夹具应能获得第二个荣耀战车底盘")
	if spare_chassis.is_ok:
		bundle = spare_chassis.value
		var field_swap := authority.execute({
			"type": "equip_vehicle_item",
			"instance_id": "inventory.spare_chassis",
			"location": 0,
			"inventory_revision": int(bundle.inventory.revision),
			"loadout_revision": int(bundle.vehicle.revision),
			"_authoritative_vehicle_combat_active": true,
		})
		_expect(not field_swap.is_ok and field_swap.error_code \
				== &"equipment.chassis_change_forbidden_in_field",
			"野外地图必须拒绝更换战车底盘")
		var occupied_swap := authority.execute({
			"type": "equip_vehicle_item",
			"instance_id": "inventory.spare_chassis",
			"location": 0,
			"inventory_revision": int(bundle.inventory.revision),
			"loadout_revision": int(bundle.vehicle.revision),
		})
		_expect(not occupied_swap.is_ok and occupied_swap.error_code \
				== &"equipment.chassis_change_requires_empty_loadout",
			"室内更换底盘前必须先卸下全部其他战车装备")

		for location: int in [3, 1, 0]:
			var latest := authority.execute({"type": "query"})
			_expect(latest.is_ok, "连续卸装前应能读取最新 revision")
			if not latest.is_ok:
				break
			bundle = latest.value
			var unloaded := authority.execute({
				"type": "unequip_vehicle_item",
				"location": location,
				"inventory_revision": int(bundle.inventory.revision),
				"loadout_revision": int(bundle.vehicle.revision),
			})
			_expect(unloaded.is_ok, "按推进器、主炮、底盘顺序应可在室内清空装配")
		var empty_bundle_result := authority.execute({"type": "query"})
		if empty_bundle_result.is_ok:
			bundle = empty_bundle_result.value
			var engine_instance_id := ""
			for item: Dictionary in bundle.inventory.items:
				if String(item.get("definition_id", "")) == "beginner_engine":
					engine_instance_id = String(item.get("instance_id", ""))
					break
			var engine_without_chassis := authority.execute({
				"type": "equip_vehicle_item",
				"instance_id": engine_instance_id,
				"location": 3,
				"inventory_revision": int(bundle.inventory.revision),
				"loadout_revision": int(bundle.vehicle.revision),
			})
			_expect(not engine_without_chassis.is_ok and engine_without_chassis.error_code \
					== &"equipment.chassis_required",
				"没有底盘时必须拒绝安装推进器等其他装备")
	_finish()


## 汇总断言并退出独立测试进程。
func _finish() -> void:
	if failures.is_empty():
		print("PLAYER_PANEL_SERVICE_OK (%d assertions)" % assertions)
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
