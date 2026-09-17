extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证满仓库在普通人物事务中不加载装备，并隔离不同事务的可变物品。
func _initialize() -> void:
	var catalog := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok, "初始化")
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	player.warehouse = PersonalWarehouse.new()
	player.warehouse._cabinets.clear()
	for c in 6:
		var cabinet := Inventory.new()
		for i in 40:
			cabinet.add_reward(catalog.create("beginner_engine", {"instance_id": "stored.%s.%s" % [c, i]}).value)
		player.warehouse._cabinets.append(cabinet)
	var saved: PlayerStateRecord = mapper.to_record(player).value
	_check(saved.warehouse.cabinet_count() == 6, "六个满柜")
	var first: Player = mapper.to_domain(saved).value
	var second: Player = mapper.to_domain(saved).value
	_check(first.warehouse is StoredPersonalWarehouse and second.warehouse is StoredPersonalWarehouse, "独立延迟对象")
	_check(first.warehouse.unchanged_record() == saved.warehouse and second.warehouse.unchanged_record() == saved.warehouse, "共享只读记录")
	_check(mapper.to_record(first).value.warehouse == saved.warehouse, "普通人物保存不重建仓库")
	_check(saved.duplicate_record().warehouse == saved.warehouse, "自动保存快照复制不展开240件物品")
	_check(not saved.to_dictionary(false).has("warehouse"), "内部复制跳过仓库序列化")
	var raw := saved.to_dictionary()
	raw.warehouse.cabinets[0][0].quantity = 99
	_check(saved.warehouse.to_dictionary().cabinets[0][0].quantity == 1, "对外字典不暴露记录可变引用")
	var start := Time.get_ticks_usec()
	for i in 10:
		var restored: Player = mapper.to_domain(saved).value
		var roundtrip: PlayerStateRecord = mapper.to_record(restored).value
		_check(roundtrip.warehouse == saved.warehouse and restored.warehouse.unchanged_record() != null, "完整普通事务未加载")
	print("WAREHOUSE_240_ROUNDTRIP_MS ", (Time.get_ticks_usec() - start) / 10000.0)
	_check(first.warehouse.materialize().is_ok and first.warehouse.unchanged_record() == null, "显式访问加载")
	_check(second.warehouse.unchanged_record() == saved.warehouse, "另一事务保持延迟")
	var taken := first.warehouse.transfer(first.inventory, 1, false, "stored.0.0", 1, first.inventory.revision, 0, "unused")
	_check(taken.is_ok and first.warehouse.items(1).size() == 39, "首个事务取走一件")
	_check(second.warehouse.find("stored.0.0") != null and second.warehouse.items(1).size() == 40, "其他事务没有被取走物品")
	_check(saved.warehouse.to_dictionary().cabinets[0].size() == 40, "原提交快照没有被修改")
	var changed: PlayerStateRecord = mapper.to_record(first).value
	_check(changed.warehouse != saved.warehouse and changed.warehouse.to_dictionary().cabinets[0].size() == 39, "变更产生新记录")
	var disk := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(changed.to_dictionary())))
	_check(disk.is_ok and mapper.to_domain(disk.value).value.warehouse.items(1).size() == 39, "真实磁盘格式往返")
	var corrupt := saved.to_dictionary()
	corrupt.warehouse.cabinets[0][0].item_definition_id = "missing.definition"
	var malformed := PlayerStateRecord.from_dictionary(corrupt)
	_check(malformed.is_ok, "存档结构有效但物品定义失踪")
	var damaged: Player = mapper.to_domain(malformed.value).value
	_check(not damaged.warehouse.materialize().is_ok, "访问错误明确返回")
	_check(mapper.to_record(damaged).value.warehouse.to_dictionary() == corrupt.warehouse, "加载失败不能保存为空仓库")
	print("Warehouse snapshots: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总快照、持久化及加载隔离检查。
## [param condition] 实际结果。
## [param message] 故障说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
