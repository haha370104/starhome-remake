extends SceneTree

const FixedInventory = preload("res://scripts/domain/inventory/fixed_inventory.gd")
const InventoryItem = preload("res://scripts/domain/inventory/inventory_item.gd")
const JsonConfigLoader = preload("res://scripts/core/json_config_loader.gd")
const SkillProgression = preload("res://scripts/domain/skills/skill_progression.gd")
const SkillState = preload("res://scripts/domain/skills/skill_state.gd")
const VehicleMovement = preload("res://scripts/domain/vehicles/vehicle_movement.gd")
const SKILL_CONFIG_PATH := "res://data/gameplay/skill_progression.json"
const VEHICLE_CONFIG_PATH := "res://data/gameplay/vehicle_movement.json"
const INVENTORY_CONFIG_PATH := "res://data/gameplay/inventory.json"

var _passed := 0
var _failed := 0


## 运行领域层冒烟测试并根据累计断言结果结束测试进程。
## 设计：入口以进程退出码对接工程检查脚本，不依赖第三方测试框架。
func _initialize() -> void:
	_run_all()
	if _failed == 0:
		print("Domain smoke tests passed: %d" % _passed)
		quit(0)
	else:
		push_error("Domain smoke tests failed: %d passed, %d failed" % [_passed, _failed])
		quit(1)


## 加载共享配置夹具并依次验证技能、载具移动和物品栏规则。
## 设计：配置仅在此处读取一次，再显式传入各领域用例以隔离文件 I/O。
func _run_all() -> void:
	var skill_config := _load_config(SKILL_CONFIG_PATH)
	var vehicle_config := _load_config(VEHICLE_CONFIG_PATH)
	var inventory_config := _load_config(INVENTORY_CONFIG_PATH)
	if skill_config.is_empty() or vehicle_config.is_empty() or inventory_config.is_empty():
		return
	_test_skill_thresholds(skill_config)
	_test_skill_grants(skill_config)
	_test_vehicle_movement(vehicle_config)
	_test_inventory(inventory_config)


## 执行 `test_skill_thresholds` 对应的模块操作。
## [param config] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _test_skill_thresholds(config: Dictionary) -> void:
	_expect_equal(SkillProgression.get_need_points(&"energy_cannon", 0, config).value, 1, "energy cannon level 0 threshold")
	_expect_equal(SkillProgression.get_need_points(&"energy_cannon", 49, config).value, 3750, "energy cannon boundary before coefficient change")
	_expect_equal(SkillProgression.get_need_points(&"energy_cannon", 50, config).value, 5202, "energy cannon boundary after coefficient change")
	_expect_equal(SkillProgression.get_need_points(&"mining", 10, config).value, 4, "mining fractional formula floors")
	_expect_false(SkillProgression.get_need_points(&"unknown", 0, config).is_ok, "unknown skill is rejected")
	_expect_false(SkillProgression.get_need_points(&"driving", -1, config).is_ok, "negative level is rejected")


## 执行 `test_skill_grants` 对应的模块操作。
## [param config] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _test_skill_grants(config: Dictionary) -> void:
	var state := SkillState.new(&"energy_cannon", 20, 100, 0.25)
	var threshold: int = int(SkillProgression.get_need_points(state.skill_id, state.level, config).value)
	var upgrade := SkillProgression.apply_exp(state, float(threshold) + 10000.5, config)
	_expect_true(upgrade.is_ok and bool(upgrade.value["upgraded"]), "large grant upgrades")
	_expect_equal(state.level, 21, "one grant upgrades exactly one level")
	_expect_equal(state.current_exp, 0, "upgrade clears integer overflow")
	_expect_near(state.fractional_exp, 0.0, "upgrade clears fractional overflow")

	var fractional_state := SkillState.new(&"mining", 10, 1, 0.25)
	var partial := SkillProgression.apply_exp(fractional_state, 1.5, config)
	_expect_true(partial.is_ok and not bool(partial.value["upgraded"]), "partial grant does not upgrade")
	_expect_equal(fractional_state.current_exp, 2, "partial grant accumulates integer experience")
	_expect_near(fractional_state.fractional_exp, 0.75, "partial grant preserves fraction")
	var snapshot := fractional_state.to_dictionary()
	var rejected := SkillProgression.apply_exp(fractional_state, -1.0, config)
	_expect_false(rejected.is_ok, "negative grant is rejected")
	_expect_equal(fractional_state.to_dictionary(), snapshot, "rejected grant is atomic")

	var max_state := SkillState.new(&"driving", int(config["maximum_level"]))
	_expect_false(SkillProgression.apply_exp(max_state, 1.0, config).is_ok, "maximum level cannot upgrade")


## 执行 `test_vehicle_movement` 对应的模块操作。
## [param config] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _test_vehicle_movement(config: Dictionary) -> void:
	var full := VehicleMovement.base_speed(10, 10, 20, [50, 50], config)
	_expect_true(full.is_ok, "valid vehicle speed succeeds")
	_expect_equal(full.value["effective_propulsion"], 20, "qualified driver receives full propulsion")
	_expect_equal(full.value["speed"], 240, "base vehicle speed is capped at 240")
	var underqualified := VehicleMovement.base_speed(5, 10, 20, [100, 100], config)
	_expect_equal(underqualified.value["effective_propulsion"], 10, "driving skill scales propulsion")
	_expect_equal(underqualified.value["speed"], 75, "scaled propulsion and all equipment weight determine speed")
	var no_requirement := VehicleMovement.base_speed(0, 0, 20, [200], config)
	_expect_equal(no_requirement.value["effective_propulsion"], 20, "zero-level engine avoids division and uses full propulsion")
	var no_weight := VehicleMovement.base_speed(10, 10, 20, [], config)
	_expect_equal(no_weight.value["speed"], 0, "zero total weight produces zero speed")
	_expect_false(VehicleMovement.base_speed(10, 10, 20, [10, -1], config).is_ok, "negative component weight is rejected")
	_expect_false(VehicleMovement.base_speed(10, 10, -1, [], config).is_ok, "negative propulsion is rejected even without weight")


## 执行 `test_inventory` 对应的模块操作。
## [param config] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：每个失败分支都与操作前快照比较，确保领域事务不会部分提交。
func _test_inventory(config: Dictionary) -> void:
	var capacity: int = int(config["person_bag_capacity"])
	var bag := FixedInventory.new(capacity)
	_expect_equal(capacity, 40, "person inventory capacity comes from configuration")
	var iron_a := InventoryItem.new("iron-a", &"iron", 7, 10)
	_expect_true(bag.add_item(iron_a).is_ok, "first stack is inserted")
	var iron_b := InventoryItem.new("iron-b", &"iron", 5, 10)
	_expect_true(bag.add_item(iron_b).is_ok, "stack merges and uses an empty slot atomically")
	_expect_equal(bag.count_template(&"iron"), 12, "merged and remainder quantities are conserved")
	_expect_equal(bag.occupied_slots(), 2, "stack remainder occupies one additional slot")
	_expect_equal(bag.item_at(0).quantity, 10, "first compatible stack is filled")
	_expect_equal(bag.item_at(1).quantity, 2, "remainder keeps incoming item identity")

	var before_failed_remove := bag.to_dictionary()
	_expect_false(bag.remove_template(&"iron", 13).is_ok, "insufficient template removal is rejected")
	_expect_equal(bag.to_dictionary(), before_failed_remove, "failed template removal changes no slot")
	_expect_true(bag.remove_template(&"iron", 11).is_ok, "template removal spans stacks")
	_expect_equal(bag.count_template(&"iron"), 1, "template removal preserves exact remainder")
	_expect_false(bag.remove_instance("missing", 1).is_ok, "missing instance removal is rejected")
	_expect_false(bag.add_item(InventoryItem.new("bad", &"iron", 11, 10)).is_ok, "overfull incoming stack is rejected")

	var full_bag := FixedInventory.new(capacity)
	for index: int in range(capacity):
		_expect_true(full_bag.add_item(InventoryItem.new("unique-%d" % index, &"unique", 1, 1)).is_ok, "fill inventory slot %d" % index)
	var full_snapshot := full_bag.to_dictionary()
	_expect_false(full_bag.add_item(InventoryItem.new("overflow", &"overflow", 1, 1)).is_ok, "full inventory rejects complete add")
	_expect_equal(full_bag.to_dictionary(), full_snapshot, "failed add is atomic")


## 执行 `load_config` 对应的模块操作。
## [param path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _load_config(path: String) -> Dictionary:
	var result := JsonConfigLoader.load_dictionary(path)
	_expect_true(result.is_ok, "load configuration %s" % path)
	return {} if not result.is_ok else result.value


## 执行 `expect_true` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_true(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: %s" % label)


## 执行 `expect_false` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_false(condition: bool, label: String) -> void:
	_expect_true(not condition, label)


## 执行 `expect_equal` 对应的模块操作。
## [param actual] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param expected] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_expect_true(actual == expected, "%s (expected %s, got %s)" % [label, str(expected), str(actual)])


## 执行 `expect_near` 对应的模块操作。
## [param actual] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param expected] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_near(actual: float, expected: float, label: String) -> void:
	_expect_true(is_equal_approx(actual, expected), "%s (expected %f, got %f)" % [label, expected, actual])
