extends SceneTree

var _checks := 0
var _failures := PackedStringArray()
var _catalog := ItemCatalog.new()
var _fixture := PlayerPanelServiceFixture.new()


## 穷举全部原表装备与四档返还，验证失败、容量和绑定不会造成半笔事务。
func _initialize() -> void:
	_check(_catalog.initialize().is_ok and _fixture.initialize().is_ok, "initialize")
	_check(_catalog.dismantle_rules.profiles.size() == 15, "all original rows")
	for id: String in _catalog.dismantle_rules.profiles:
		for index in 4:
			var player := _player(id)
			var before := _snapshot(player)
			var preview := PlayerEquipmentDismantleActions.preview(player, _catalog, "source", "preview")
			_check(preview.is_ok and _snapshot(player) == before, "preview no mutation")
			var revision := player.inventory.revision
			var result := PlayerEquipmentDismantleActions.execute(player, _catalog, "source", revision, true, [0.1, 0.3, 0.5, 0.95][index], "result")
			_check(result.is_ok and result.value.outcome_index == index, "probability branch")
			_check(player.inventory.find("source") == null and player.inventory.currency == 800 and player.inventory.revision == revision + 1, "single atomic payment")
			var outcome: EquipmentDismantleRules.Outcome = _catalog.dismantle_rules.profiles[id].outcomes[index]
			for material: Dictionary in outcome.materials:
				_check(player.inventory.count_definition(material.definition_id) == int(material.quantity), "full return split across stacks")
			for item: GameItem in player.inventory.items():
				_check(item.bound and item.quantity <= item.max_stack, "binding and stack caps")
			_check(not PlayerEquipmentDismantleActions.execute(player, _catalog, "source", revision, true, 0.95, "replay").is_ok, "replay rejected")
			var mapper := PlayerStateMapper.new(_catalog)
			var record := mapper.to_record(player)
			_check(record.is_ok and mapper.to_domain(record.value).is_ok, "persist complete result")
	_test_rejections()
	print("Equipment dismantling: %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures: push_error(failure)
	quit(0 if _failures.is_empty() else 1)


## 用独立玩家检查所有前置失败和最差容量，不通过概率逃避满包检查。
func _test_rejections() -> void:
	var id := "glory_equipment_gun8_e7ce1423fa"
	for reason in ["white", "locked", "currency", "slots", "worst_capacity", "unconfirmed", "revision", "nan", "identity"]:
		var player := _player(id)
		var item := player.inventory.find("source") as VehicleEquipment
		match reason:
			"white": item.quality.grade = 0
			"locked": item.locked = true
			"currency": player.inventory.currency = 199
			"slots": player.inventory.capacity = 3
			"worst_capacity": player.inventory.capacity = 4
			"identity":
				player.inventory.add_reward(_catalog.create("beginner_engine", {"instance_id": "result.1.0"}).value)
		var before := _snapshot(player)
		var result := PlayerEquipmentDismantleActions.execute(player, _catalog, "source", player.inventory.revision + int(reason == "revision"), reason != "unconfirmed", NAN if reason == "nan" else 0.05, "result")
		_check(not result.is_ok and _snapshot(player) == before, "no partial mutation " + reason)
	var player := _player("glory_equipment_tank7_6dce9d1c52")
	var source := player.inventory.find("source") as VehicleEquipment
	source.bound = false
	source.sockets._slots[0].opened = true
	source.sockets._slots[0].crystal_id = "bright_firepower_crystal"
	source.sockets._slots[0].bound = true
	source.strengthening.level = 2
	source.refresh_processed_stats()
	var result := PlayerEquipmentDismantleActions.execute(player, _catalog, "source", player.inventory.revision, true, 0.95, "crystal.bound")
	_check(result.is_ok and player.inventory.count_definition("bright_firepower_crystal") == 0, "crystals and growth consumed")
	for output: GameItem in player.inventory.items(): _check(output.bound, "bound crystal prevents laundering")
	var empty := _player("recruit_tank")
	_check(not PlayerEquipmentDismantleActions.preview(empty, _catalog, "source", "preview").is_ok, "unsupported starter")


## 构建只有一件待拆装备的隔离玩家。
## [param id] 原表装备或拒绝测试定义。
## 返回不接触真实存档的玩家。
func _player(id: String) -> Player:
	var player: Player = PlayerStateMapper.new(_catalog).to_domain(_fixture._state).value
	player.inventory = Inventory.new(40, 0, 1000)
	var state := {"instance_id": "source", "bound": true}
	if _catalog.quality_rules.profiles.has(id): state["equipment_quality"] = {"version": 1, "grade": 1}
	player.inventory.add_reward(_catalog.create(id, state).value)
	return player


## 记录库存及钱包的确定性快照，检测失败污染。
## [param player] 被检查玩家。
## 返回完整库存序列化。
func _snapshot(player: Player) -> String:
	return JSON.stringify(PlayerStateMapper.new(_catalog).to_record(player).value.to_dictionary())


## 累计断言。
## [param condition] 期望值。
## [param label] 故障标签。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition: _failures.append(label)
