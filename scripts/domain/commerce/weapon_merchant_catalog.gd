class_name WeaponMerchantCatalog
extends RefCounted

const CONFIG_PATH := "res://data/gameplay/commerce/weapon_merchant_v1.json"

var _item_catalog: ItemCatalog
var _config: Dictionary = {}
var _offers: Array[Dictionary] = []


## 读取荣耀装备目录并建立武器商人可售清单。
## [param item_catalog] 已初始化的统一物品目录。
## 返回目录实例或配置错误。
func initialize(item_catalog: ItemCatalog) -> DomainResult:
	_item_catalog = item_catalog
	var loaded := JsonConfigLoader.load_dictionary(CONFIG_PATH)
	if not loaded.is_ok:
		return loaded
	_config = loaded.value
	var merchant_value: Variant = _config.get("merchant")
	if not merchant_value is Dictionary:
		return DomainResult.failure(&"commerce.invalid_config", "merchant definition is missing")
	_offers.clear()
	for definition_id: String in _item_catalog.definition_ids():
		var definition := _item_catalog.definition(definition_id)
		var category := _merchant_category(definition)
		if category.is_empty() or not _is_sellable(definition):
			continue
		_offers.append(_offer(definition, category))
	_offers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
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


func _is_sellable(definition: Dictionary) -> bool:
	var stats: Dictionary = definition.get("stats", {})
	var properties: Dictionary = stats.get("legacy_properties", {})
	var price := int(stats.get("purchase_value", 0))
	var level_cap := int((_config["merchant"] as Dictionary).get("maximum_required_level", 270))
	var name := String(definition.get("display_name", ""))
	return price > 0 and _required_level(properties) <= level_cap \
		and int(properties.get("m_nCanSell", 1)) != 0 \
		and "GM专用" not in name and "（赠）" not in name and "（绑）" not in name


func _merchant_category(definition: Dictionary) -> String:
	match String(definition.get("kind", "")):
		"vehicle_chassis": return "vehicle_chassis"
		"energy_cannon": return "energy_cannon"
		"vehicle_engine": return "vehicle_engine"
		"vehicle_equipment":
			var name := String(definition.get("display_name", ""))
			if "维修臂" in name:
				return "repair_arm"
			if "挖掘臂" in name:
				return "mining_arm"
	return ""


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
