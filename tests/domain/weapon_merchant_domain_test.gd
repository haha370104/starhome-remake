extends SceneTree

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const MerchantCatalogScript := preload("res://scripts/domain/commerce/weapon_merchant_catalog.gd")
const TaskScript := preload("res://scripts/domain/quests/repeatable_collection_task.gd")

var failures := PackedStringArray()
var assertions := 0


func _initialize() -> void:
	var items = ItemCatalogScript.new()
	var loaded: DomainResult = items.initialize()
	_expect(loaded.is_ok, "统一物品目录应加载")
	var merchant = MerchantCatalogScript.new()
	var merchant_loaded: DomainResult = merchant.initialize(items)
	_expect(merchant_loaded.is_ok, "武器商人目录应加载")
	if not merchant_loaded.is_ok:
		_finish()
		return
	var offers: Array[Dictionary] = merchant.offers()
	_expect(not offers.is_empty(), "武器商人应有荣耀装备可售")
	_expect(not merchant.offer("glory_equipment_gun1_216568dc50").is_empty(), "新兵能量炮应在售")
	_expect(merchant.offer("glory_equipment_gun9_d2426d05e9").is_empty(), "高于270级装备不应在售")
	_expect(_all_offers_valid(offers), "在售项必须属于五类且不超过270级")
	var inventory := Inventory.new(40, 0, 0)
	for definition_id: String in [
		"item:material:02ff69f031b5",
		"item:material:e07b300afb44",
		"item:material:fc4cebd5d85b",
	]:
		var created: DomainResult = items.create(definition_id, {
			"instance_id": "test.%s" % definition_id,
			"quantity": 20,
		})
		_expect(created.is_ok and inventory.add_reward(created.value).is_ok, "任务材料应可加入背包")
	var task_definition: Dictionary = (merchant.config()["repeatable_task"] as Dictionary)
	var task = TaskScript.new(task_definition)
	var accepted: DomainResult = task.accept({})
	_expect(accepted.is_ok, "循环任务应可领取")
	var progress: Dictionary = task.snapshot(inventory, accepted.value)
	_expect(bool(progress["ready_to_turn_in"]), "三种材料各20个时应可交付")
	var completed: DomainResult = task.turn_in(inventory, accepted.value)
	_expect(completed.is_ok and int(completed.value["currency_reward"]) == 1500, "交付应奖励1500金币")
	_expect(int((completed.value["state"] as Dictionary)["completions"]) == 1, "交付应累计完成次数")
	_expect(inventory.count_definition("item:material:02ff69f031b5") == 0, "交付应消耗材料")
	_finish()


func _all_offers_valid(offers: Array[Dictionary]) -> bool:
	var categories := ["vehicle_chassis", "energy_cannon", "vehicle_engine", "repair_arm", "mining_arm"]
	for offer: Dictionary in offers:
		if String(offer["category"]) not in categories or int(offer["required_level"]) > 270:
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_MERCHANT_DOMAIN_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
