extends SceneTree

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const MerchantCatalogScript := preload("res://scripts/domain/commerce/weapon_merchant_catalog.gd")
const TaskScript := preload("res://scripts/domain/quests/repeatable_collection_task.gd")

var failures := PackedStringArray()
var assertions := 0


## 验证普通与特殊武器商人的官网白名单、分组排序和等级上限。
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
	_expect(not merchant.offer("glory_equipment_gun9_d2426d05e9").is_empty(), "官网280级虎式突袭能量炮应在售")
	_expect(_all_offers_valid(offers), "在售项必须属于五类官网清单且不超过280级")
	_expect(String(offers[0]["category"]) == "vehicle_engine", "普通商店必须先列引擎")
	var special = MerchantCatalogScript.new()
	var special_loaded: DomainResult = special.initialize(items, "special_weapon_merchant")
	_expect(special_loaded.is_ok, "特殊武器商人目录应加载")
	if special_loaded.is_ok:
		var special_offers: Array[Dictionary] = special.offers()
		_expect(not special_offers.is_empty(), "特殊武器商人应有官网装备可售")
		_expect(String(special_offers[0]["category"]) == "rocket_weapon", "特殊商店必须先列火箭")
		_expect(not special.offer("official_rocket_firegun_7").is_empty(), "240级劲弩式火箭应在售")
		_expect(not special.offer("glory_equipment_missile5_15584171c6").is_empty(), "280级大力神导弹应在售")
		_test_equipment_prices(merchant, special, items)
	_test_ground_mining_arms(offers, items)
	var inventory := Inventory.new(40, 0, 0)
	for definition_id: String in [
		"low_grade_gel",
		"low_grade_energy_catalyst",
		"low_grade_biosilicon",
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
	_expect(inventory.count_definition("low_grade_gel") == 0, "交付应消耗材料")
	_finish()


## 校验用户确认的翻倍定价及跨商人一致的回收价，并确保原始数据仍可溯源。
## [param merchant] 出售地面装备的普通武器商人。
## [param special] 同样可以回收物品的特殊武器商人。
## [param items] 保留原始源码字段的统一物品目录。
func _test_equipment_prices(merchant: WeaponMerchantCatalog, special: WeaponMerchantCatalog, items: ItemCatalog) -> void:
	var expected := {
		"glory_equipment_tank7_6dce9d1c52": 100000,
		"glory_equipment_tank8_eccf445ff5": 200000,
		"glory_equipment_engine7_24246159c0": 50000,
		"glory_equipment_engine8_df38922e4b": 100000,
		"glory_equipment_gun8_e7ce1423fa": 80000,
		"glory_equipment_gun9_d2426d05e9": 160000,
	}
	for definition_id: String in expected:
		var price: int = expected[definition_id]
		var offer := merchant.offer(definition_id)
		_expect(int(offer.get("price", 0)) == price, "高档装备应按前档翻倍定价：%s" % definition_id)
		var sell_price := price >> 1
		_expect(int(offer.get("sell_price", 0)) == sell_price, "商品投影应给出对应回收价")
		_expect(merchant.purchase_price(definition_id) == sell_price, "普通商人回收价应为售价一半")
		_expect(special.purchase_price(definition_id) == sell_price, "特殊商人必须共用同一回收价")
		_expect(int(items.definition(definition_id)["stats"]["legacy_properties"]["m_nWorth"]) == 2000,
			"复刻经济调整不得篡改原始源码价格证据")
	_expect(int(merchant.offer("glory_equipment_tank6_bb6cdb6f5c")["price"]) == 50000,
		"作为翻倍基准的190级战车价格应保持不变")


## 验证本期只出售普通地面挖掘臂，排除太空分支、特殊型号及超等级型号。
## [param offers] 当前商人商品列表。
## [param items] 用于核对装备类别的统一物品目录。
func _test_ground_mining_arms(offers: Array[Dictionary], items: ItemCatalog) -> void:
	var names: Array[String] = []
	for offer: Dictionary in offers:
		if offer["category"] != "mining_arm":
			continue
		names.append(String(offer["display_name"]))
		var definition := items.definition(String(offer["definition_id"]))
		_expect(int(definition["stats"]["legacy_properties"]["m_nEquipKind2"]) == 4,
			"在售挖掘臂必须属于地面类别4，不能混入太空类别102")
	_expect(names == ["初级挖掘臂", "改式挖掘臂", "精度挖掘臂", "多空挖掘臂", "磁性挖掘臂", "电磁挖掘臂", "磁导挖掘臂"],
		"挖掘臂应仅保留10至250级七档普通地面型号，并按等级排列")


## 检查所有商品是否满足价格、等级和展示字段约束。
## [param offers] 服务端商品投影数组。
## 返回全部商品是否合法。
func _all_offers_valid(offers: Array[Dictionary]) -> bool:
	var categories := ["vehicle_chassis", "energy_cannon", "vehicle_engine", "repair_arm", "mining_arm"]
	for offer: Dictionary in offers:
		if String(offer["category"]) not in categories or int(offer["required_level"]) > 280:
			return false
	return true


## 记录一条测试断言。
## [param condition] 条件是否成立。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出测试结果并结束进程。
func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_MERCHANT_DOMAIN_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
