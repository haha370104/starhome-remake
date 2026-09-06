class_name WeaponMerchantCatalog
extends RefCounted

const CONFIG_PATHS := {
	"weapon_merchant": "res://data/gameplay/commerce/weapon_merchant_v1.json",
	"special_weapon_merchant": "res://data/gameplay/commerce/special_weapon_merchant_v1.json",
}

var _item_catalog: ItemCatalog
var _config: Dictionary = {}
var _merchant_config: Dictionary = {}
var _offers: Array[Dictionary] = []


## 读取荣耀装备目录并建立武器商人可售清单。
## [param item_catalog] 已初始化的统一物品目录。
## [param merchant_id] 商人业务标识，用于选择普通或特殊武器目录。
## 返回目录实例或配置错误。
func initialize(item_catalog: ItemCatalog, merchant_id := "weapon_merchant") -> DomainResult:
	_item_catalog = item_catalog
	var config_path := String(CONFIG_PATHS.get(merchant_id, ""))
	if config_path.is_empty():
		return DomainResult.failure(&"commerce.merchant_missing", "merchant is not registered")
	var loaded := JsonConfigLoader.load_dictionary(config_path)
	if not loaded.is_ok:
		return loaded
	_config = loaded.value
	var merchant_value: Variant = _config.get("merchant")
	if not merchant_value is Dictionary:
		return DomainResult.failure(&"commerce.invalid_config", "merchant definition is missing")
	_merchant_config = (merchant_value as Dictionary).duplicate(true)
	_offers.clear()
	for definition_id: String in _item_catalog.definition_ids():
		var definition := _item_catalog.definition(definition_id)
		var category := _merchant_category(definition)
		if category.is_empty() or not _is_sellable(definition):
			continue
		_offers.append(_offer(definition, category))
	_offers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_category := _category_order(String(left["category"]))
		var right_category := _category_order(String(right["category"]))
		if left_category != right_category:
			return left_category < right_category
		if int(left["required_level"]) != int(right["required_level"]):
			return int(left["required_level"]) < int(right["required_level"])
		return String(left["display_name"]) < String(right["display_name"])
	)
	return DomainResult.ok(self)


## 返回客户端商店所需的安全商品 DTO。
func offers() -> Array[Dictionary]:
	return _offers.duplicate(true)


## 按定义查询一项在售商品。
## [param definition_id] 统一物品定义标识。
## 返回商品 DTO；不在售时返回空字典。
func offer(definition_id: String) -> Dictionary:
	for value: Dictionary in _offers:
		if String(value["definition_id"]) == definition_id:
			return value.duplicate(true)
	return {}


## 按原版 m_nSell 计算玩家物品收购价。
## [param definition_id] 统一物品定义标识。
## 返回非负单价；未知物品或禁交易物品为 0。
func purchase_price(definition_id: String) -> int:
	var definition := _item_catalog.definition(definition_id)
	if definition.is_empty():
		return 0
	var stats: Dictionary = definition.get("stats", {})
	var original_sell_value := int(stats.get("sell_value", 0))
	var original_purchase_value := int(stats.get("purchase_value", 0))
	return maxi(1, maxi(original_sell_value, floori(float(original_purchase_value) / 2.0)))


## 返回武器商人及循环任务配置的防御性副本。
func config() -> Dictionary:
	return _config.duplicate(true)


## 返回当前商人的安全配置副本。
func merchant_config() -> Dictionary:
	return _merchant_config.duplicate(true)


## 判断物品是否满足价格、等级、交易标记与官网白名单约束。
## [param definition] 统一物品目录中的定义。
## 返回允许商人出售时为 true。
func _is_sellable(definition: Dictionary) -> bool:
	var stats: Dictionary = definition.get("stats", {})
	var properties: Dictionary = stats.get("legacy_properties", {})
	var price := int(stats.get("purchase_value", 0))
	var level_cap := int(_merchant_config.get("maximum_required_level", 280))
	var name := String(definition.get("display_name", ""))
	var category := _merchant_category(definition)
	var whitelist_value: Variant = _merchant_config.get("official_whitelist_ids", {})
	var whitelist: Dictionary = whitelist_value if whitelist_value is Dictionary else {}
	var category_ids_value: Variant = whitelist.get(category, [])
	var category_ids: Array = category_ids_value if category_ids_value is Array else []
	var whitelisted := category_ids.is_empty() or String(definition.get("id", "")) in category_ids
	return whitelisted and price > 0 and _required_level(properties) <= level_cap \
		and int(properties.get("m_nCanSell", 1)) != 0 \
		and "GM专用" not in name and "（赠）" not in name and "（绑）" not in name


## 将领域物品类型归入当前商人支持的商品分组。
## [param definition] 统一物品定义。
## 返回配置中启用的分类标识；不属于商人经营范围时返回空字符串。
func _merchant_category(definition: Dictionary) -> String:
	var category := ""
	match String(definition.get("kind", "")):
		"vehicle_chassis": category = "vehicle_chassis"
		"energy_cannon": category = "energy_cannon"
		"vehicle_engine": category = "vehicle_engine"
		"missile_weapon": category = "missile_weapon"
		"rocket_weapon": category = "rocket_weapon"
		"vehicle_equipment":
			var name := String(definition.get("display_name", ""))
			if "维修臂" in name:
				category = "repair_arm"
			elif "挖掘臂" in name:
				category = "mining_arm"
			elif "隐身装置" in name:
				category = "stealth_device"
			elif "雷达装置" in name:
				category = "radar_device"
	var enabled_value: Variant = _merchant_config.get("sell_categories", [])
	var enabled: Array = enabled_value if enabled_value is Array else []
	return category if category in enabled else ""


## 从旧客户端装备字段解析商店使用等级。
## [param properties] 旧 FCC 属性字典。
## 返回用于分组排序和等级上限判断的非负等级。
func _required_level(properties: Dictionary) -> int:
	# 原版商店的“X级装备”以 m_nSkillLevel 分档；m_nneedgrade 是另一套
	# 装备品质/强化门槛，例如加强能量炮为 1000，不能拿来当玩家等级。
	var skill_level := int(properties.get("m_nSkillLevel", 0))
	if skill_level > 0:
		return skill_level
	return maxi(
		int(properties.get("m_ndrive", 0)),
		int(properties.get("m_nRepairLevel", 0)),
	)


## 把完整物品定义投影为客户端商店商品 DTO。
## [param definition] 统一物品定义。
## [param category] 已解析的商人分类。
## 返回不含服务端内部引用的商品字典。
func _offer(definition: Dictionary, category: String) -> Dictionary:
	var stats: Dictionary = definition.get("stats", {})
	var properties: Dictionary = stats.get("legacy_properties", {})
	var presentation: Dictionary = definition.get("presentation", {})
	return {
		"definition_id": String(definition.get("id", "")),
		"display_name": String(definition.get("display_name", "")),
		"description": String(definition.get("description", "")),
		"category": category,
		"required_level": _required_level(properties),
		"price": int(stats.get("purchase_value", 0)),
		"sell_price": int(stats.get("sell_value", 0)),
		"presentation": presentation.duplicate(true),
	}


## 返回分类在商人配置中的稳定顺序。
## [param category] 商品分类标识。
## 返回从零开始的顺序；未知分类排在末尾。
func _category_order(category: String) -> int:
	var categories_value: Variant = _merchant_config.get("sell_categories", [])
	var categories: Array = categories_value if categories_value is Array else []
	var index := categories.find(category)
	return index if index >= 0 else categories.size()
