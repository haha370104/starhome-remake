extends SceneTree

var failures: Array[String] = []
var catalog := ItemCatalog.new()


## 验证目录食品效果及独立堆叠领域不变量。
func _initialize() -> void:
	_expect(catalog.initialize().is_ok, "初始化目录")
	_test_foods()
	_test_stacks()
	for failure: String in failures:
		push_error(failure)
	print("CONSUMABLE_STACK_CHECKS failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


## 遍历全部规则，并验证原版类型、冷却、替换、到期和离线回血。
func _test_foods() -> void:
	var rules: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/consumable_effects_v1.json").value.rules
	_expect(rules.size() == 34, "31种食品、2种能量包及兼容的旧能量包定义")
	for id: String in rules:
		var item: ConsumableItem = catalog.create(id, {"instance_id": id}).value
		_expect(item != null and not item.use_description().is_empty(), "规则均组装为可使用类型")
		for effect: FoodEffect in item.effects:
			_expect(effect.kind > 0 and effect.kind <= 19 and effect.amount > 0, "有效原版效果")
			if effect.kind <= 12:
				_expect(FoodEffect.SKILLS[effect.kind] in SkillBook.ORDERED_SKILLS, "经验技能映射存在")
	var status := FoodStatus.new({"physical": 95})
	var cheese := _food("奶酪")
	status.eat(cheese, 1000)
	_expect(status.physical == 100 and status.bonus(17, 1000) == 5, "奶酪恢复体力并增加5防御")
	_expect(not status.can_eat(cheese, 1000).is_ok and status.can_eat(cheese, 1001).is_ok, "同类冷却")
	status.eat(_food("鳗鱼饭团"), 1001)
	status.eat(_food("比萨"), 1001)
	_expect(status.active.size() == 2 and status.bonus(17, 1001) == 10 and status.bonus(13, 1001) == 10, "同类替换异类共存")
	status.advance(2801)
	_expect(status.active.is_empty() and status.bonus(17, 2801) == 0, "到期回收")
	status.eat(_food("龙舌兰酒"), 5000)
	_expect(status.advance(5003) == 30 and status.advance(5003) == 0, "每秒回血且不重复结算")
	var restored := FoodStatus.new(status.to_dictionary())
	restored.resume(5008)
	_expect(restored.advance(5009) == 10 and restored.advance(5020) == 10, "离线不回血且只结算有效时段")
	_expect(not restored.can_eat(_food("龙舌兰酒"), 5299).is_ok, "到期后冷却仍持久化")
	_expect(restored.eat(_food("伏特加"), 6000) == 100, "伏特加即时恢复100战车生命")
	_expect(FoodStatus.valid_state(restored.to_dictionary()), "合法状态可保存")
	_expect(not FoodStatus.valid_state({"physical": NAN}) and not FoodStatus.valid_state({"active": [{"kind": 99}]}), "拒绝非法状态")


## 验证拆分不会被自动合并，容量、锁定、绑定和上限均保持原子性。
func _test_stacks() -> void:
	var inventory := Inventory.new()
	var item := _food("奶酪")
	item.quantity = 10
	item.bound = true
	_expect(inventory.restore_items([item]).is_ok, "载入堆叠")
	var result := InventoryStackActions.split(inventory, item.instance_id, 4, 0)
	_expect(result.is_ok and item.quantity == 6 and inventory.items().size() == 2, "拆出新实例")
	var copy := inventory.find(str(result.value))
	_expect(copy is ConsumableItem and copy.quantity == 4 and copy.bound, "拆分保持具体类型和绑定")
	_expect(not InventoryStackActions.merge(inventory, item.instance_id, 0).is_ok, "拒绝旧版本")
	_expect(InventoryStackActions.merge(inventory, item.instance_id, 1).is_ok and item.quantity == 10 and inventory.items().size() == 1, "合并守恒并移除空堆叠")
	inventory.capacity = 1
	_expect(not InventoryStackActions.split(inventory, item.instance_id, 3, 2).is_ok and item.quantity == 10 and inventory.revision == 2, "满包拆分失败不扣物品")
	inventory.capacity = 40
	item.locked = true
	_expect(not InventoryStackActions.split(inventory, item.instance_id, 3, 2).is_ok, "锁定禁止拆分")
	item.locked = false
	var incompatible := item.copy_stack("unbound", 5)
	incompatible.bound = false
	inventory.add_from_transfer(incompatible)
	_expect(not InventoryStackActions.merge(inventory, item.instance_id, 2).is_ok, "不同绑定不能合并")
	var overflow := item.copy_stack("overflow", 10)
	item.quantity = item.max_stack - 2
	inventory.add_from_transfer(overflow)
	_expect(InventoryStackActions.merge(inventory, item.instance_id, 2).is_ok and item.quantity == item.max_stack and overflow.quantity == 8, "合并保留超过堆叠上限的余量")


## 通过目录中文名取得真实食品，不在测试中复制生产数值。
## [param label] 原版物品名。
## 返回目录创建的食品实例。
func _food(label: String) -> ConsumableItem:
	for id: String in catalog.definition_ids():
		if catalog.display_name(id) == label:
			return catalog.create(id, {"instance_id": label}).value as ConsumableItem
	return null


## 汇总断言失败而不中断后续检查。
## [param condition] 必须成立的条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
