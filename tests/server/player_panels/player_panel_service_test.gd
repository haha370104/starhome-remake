extends SceneTree

const OfflineAuthorityScript := preload("res://scripts/client/debug/offline_player_panel_authority.gd")

var failures: PackedStringArray = []
var assertions := 0


## 验证三面板查询、像素移动、revision 冲突和原子换装。
func _initialize() -> void:
	var authority = OfflineAuthorityScript.new()
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
