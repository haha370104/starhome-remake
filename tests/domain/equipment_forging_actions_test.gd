extends SceneTree

var _checks := 0
var _failures := PackedStringArray()
var _catalog := ItemCatalog.new()
var _player: Player


## 验证每条锻造事务、失败清除、弹仓、保留成长与预检原子性。
func _initialize() -> void:
	_check(_catalog.initialize().is_ok, "catalog")
	var fixture := PlayerPanelServiceFixture.new()
	_check(fixture.initialize().is_ok, "fixture")
	_player = PlayerStateMapper.new(_catalog).to_domain(fixture._state).value
	for id: String in _catalog.forging_rules.profiles:
		var profile: EquipmentForgingRules.Profile = _catalog.forging_rules.profiles[id]
		for kind: int in profile.limits:
			var channel: EquipmentForgingRules.Channel = _catalog.forging_rules.channels[kind]
			for success: bool in [true, false]:
				_stock(id, channel)
				var original := _player.inventory.find("target") as Equipment
				original.forging.extensions[kind] = channel.step
				var revision := _player.inventory.revision
				var result := PlayerEquipmentForgingActions.execute(_player, _catalog, "target", "chip", 3, revision, true, 0.0 if success else 0.99)
				_check(result.is_ok and result.value.success == success, "outcome " + id)
				var final := _player.inventory.find("target") as Equipment
				_check(final != original and final.forging.extensions.get(kind, 0) == (channel.step * 2 if success else 0), "independent candidate")
				_check(_player.inventory.currency == 900000 and _player.inventory.count_definition(channel.material_id) == 0, "exact payment")
				_check(_player.inventory.revision == revision + 1, "one revision")
				_check(not PlayerEquipmentForgingActions.execute(_player, _catalog, "target", "chip", 3, revision, true, 0).is_ok, "reject replay")
	_test_processing_and_ammunition()
	_test_rejections()
	print("Equipment forging actions: %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures: push_error(failure)
	quit(0 if _failures.is_empty() else 1)


## 设置与真实堆叠上限一致的事务库存，不接触用户存档。
## [param id] 目标定义。
## [param channel] 本次芯片类型。
func _stock(id: String, channel: EquipmentForgingRules.Channel) -> void:
	_player.inventory = Inventory.new(40, 0, 1000000)
	_check(_player.inventory.add_reward(_catalog.create(id, {"instance_id": "target"}).value).is_ok, "target")
	_check(_player.inventory.add_reward(_catalog.create(channel.material_id, {"instance_id": "chip", "quantity": 3}).value).is_ok, "chips")
	var serial := 0
	for requirement: Dictionary in channel.requirements:
		var count := int(requirement.quantity)
		while count > 0:
			var item: GameItem = _catalog.create(requirement.definition_id, {"instance_id": "alloy.%d" % serial}).value
			item.quantity = mini(count, item.max_stack)
			count -= item.quantity
			serial += 1
			_check(_player.inventory.add_reward(item).is_ok, "alloy stack")


## 核对两种随机结果都清加工，保留品质星级且扩容不补弹。
func _test_processing_and_ammunition() -> void:
	for success: bool in [true, false]:
		_stock("starter_missile", _catalog.forging_rules.channels[6])
		var item := _player.inventory.find("target") as Equipment
		item.processing = EquipmentProcessing.restore({"increments": {"ammunition_capacity": 50, "base_attack": 2}}).value
		item.magazine.remaining = 140
		item.forging.extensions[6] = 20
		item.strengthening.level = 2
		item.durability -= 1
		item.refresh_processed_stats()
		_player.inventory.find("chip").bound = true
		var quote := PlayerEquipmentForgingActions.preview(_player, _catalog, "target", "chip", 1)
		_check(quote.is_ok and quote.value.discarded_rounds == 40, "warn discarded rounds")
		var result := PlayerEquipmentForgingActions.execute(_player, _catalog, "target", "chip", 1, _player.inventory.revision, true, 0 if success else 0.99)
		_check(result.is_ok, "magazine forging")
		var final := _player.inventory.find("target") as Equipment
		_check(final.processing.bonus("base_attack") == 0 and final.processing.bonus("ammunition_capacity") == 0, "clear all processing on both outcomes")
		_check(final.magazine.remaining == 100 and final.ammunition_capacity() == 100, "cap only no free rounds")
		_check(final.bound and final.strengthening.level == 2 and final.durability == item.durability, "preserve growth durability binding")
	_stock("glory_equipment_gun11_428a0490c6", _catalog.forging_rules.channels[5])
	var gun := _player.inventory.find("target") as Equipment
	gun.quality.grade = 3
	gun.processing = EquipmentProcessing.restore({"increments": {"base_attack": 3}}).value
	var extra_id: String = _catalog.extra_attribute_rules.allowed(gun.definition_id)[0]
	gun.extra_attributes = ExtraAttributes.restore({"version": 1, "levels": {extra_id: 2}}).value
	# 品质与锻造分别保存，制造品质不会因清加工而丢失。
	var forged := PlayerEquipmentForgingActions.execute(_player, _catalog, "target", "chip", 3, _player.inventory.revision, true, 0)
	_check(forged.is_ok and _player.inventory.find("target").quality.grade == 3, "preserve ordinary quality")
	_check(_player.inventory.find("target").extra_attributes.level(extra_id) == 2, "preserve extra growth")


## 所有拒绝都不消费任何物品或货币。
func _test_rejections() -> void:
	_stock("recruit_tank", _catalog.forging_rules.channels[1])
	var before := JSON.stringify(PlayerStateMapper.new(_catalog).to_record(_player).value.to_dictionary())
	for quantity: int in [0, 4, 999]:
		_check(not PlayerEquipmentForgingActions.execute(_player, _catalog, "target", "chip", quantity, _player.inventory.revision, true, 0).is_ok, "reject quantity")
	_check(not PlayerEquipmentForgingActions.execute(_player, _catalog, "target", "chip", 3, _player.inventory.revision, false, 0).is_ok, "confirmation required")
	_check(not PlayerEquipmentForgingActions.execute(_player, _catalog, "target", "chip", 3, _player.inventory.revision, true, NAN).is_ok, "reject invalid roll")
	_check(JSON.stringify(PlayerStateMapper.new(_catalog).to_record(_player).value.to_dictionary()) == before, "rejections atomic")
	_player.inventory.find("chip").locked = true
	_check(not PlayerEquipmentForgingActions.preview(_player, _catalog, "target", "chip", 1).is_ok, "locked material")
	_player.inventory.find("chip").locked = false
	_player.inventory.currency = 0
	_check(not PlayerEquipmentForgingActions.execute(_player, _catalog, "target", "chip", 1, _player.inventory.revision, true, 0).is_ok, "no coins")
	_check(_player.inventory.count_definition("equipment_forging_life") == 3, "no material consumed")


## 汇总断言并保留故障标识。
## [param condition] 预期条件。
## [param label] 失败说明。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition: _failures.append(label)
