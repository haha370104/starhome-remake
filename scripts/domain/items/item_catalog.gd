class_name ItemCatalog
extends RefCounted

const EquipmentSlotRegistryScript := preload("res://scripts/domain/equipment/equipment_slot_registry.gd")

const GAMEPLAY_PATHS := [
	"res://data/gameplay/stage3/starter_loadout_v1.json",
	"res://data/gameplay/character_items_v1.json",
	"res://data/gameplay/material_items_v1.json",
	"res://data/gameplay/official_rocket_items_v1.json",
	"res://data/gameplay/glory/glory_items_v1.json",
	"res://data/gameplay/industrial_materials_v1.json",
	"res://data/gameplay/commerce/attachment_upgrade_materials_v1.json",
	"res://data/gameplay/original_drop_items_v1.json",
	"res://data/gameplay/material_upgrade_items_v1.json",
	"res://data/gameplay/clothing_enhancement_items_v1.json",
]
const PRESENTATION_PATHS := [
	"res://data/presentation/player_equipment_v1.json",
	"res://data/presentation/ground_loot_v1.json",
	"res://data/presentation/recovered_equipment_v1.json",
]

var _definitions: Dictionary = {}
var _definition_ids_by_display_name: Dictionary = {}


## 读取所有当前启用的物品定义和语义化表现目录。
## 返回加载成功的目录实例或具体格式错误。
## 设计：目录负责“配置到具体类型”的组装；领域对象本身不读取文件，也不知道服务端或客户端。
func initialize() -> DomainResult:
	_definitions.clear()
	_definition_ids_by_display_name.clear()
	for path: String in GAMEPLAY_PATHS:
		var loaded := _load_gameplay_file(path)
		if not loaded.is_ok:
			return loaded
	for path: String in PRESENTATION_PATHS:
		var presentation_result := _load_presentation_file(path)
		if not presentation_result.is_ok:
			return presentation_result
		for definition_id: Variant in presentation_result.value:
			var item_id := String(definition_id)
			if not _definitions.has(item_id):
				return DomainResult.failure(
					&"items.presentation_orphan", "presentation references unknown item"
				)
			var current: Dictionary = _definitions[item_id].get("presentation", {})
			current.merge(presentation_result.value[definition_id], true)
			_definitions[item_id]["presentation"] = current
	var use_rules := JsonConfigLoader.load_dictionary("res://data/gameplay/consumable_effects_v1.json")
	if not use_rules.is_ok:
		return use_rules
	for id: String in use_rules.value.rules:
		if not _definitions.has(id):
			return DomainResult.failure(&"items.unknown_consumable", "consumable definition is missing")
		_definitions[id]["use_rule"] = use_rules.value.rules[id]
	_index_display_names()
	return DomainResult.ok(self)


## 按定义与实例状态创建具体业务类型的物品。
## [param definition_id] 配置表定义标识。
## [param state] 存档中的实例状态。
## 返回服装、战车底盘、引擎、武器、采掘臂、通用装备或普通物品的具体实例。
func create(definition_id: String, state: Dictionary) -> DomainResult:
	definition_id = ItemDefinitionAliases.canonical(definition_id)
	if not _definitions.has(definition_id):
		return DomainResult.failure(&"items.definition_missing", "item definition does not exist")
	var item_definition: Dictionary = _definitions[definition_id].duplicate(true)
	var kind := String(item_definition.get("kind", ""))
	if item_definition.has("use_rule"):
		return DomainResult.ok(ConsumableItem.new(item_definition, state))
	match kind:
		"character_clothing":
			var checked := ClothingEnhancement.restore(state.get("enhancement", {}))
			if not checked.is_ok:
				return checked
			return DomainResult.ok(Clothing.new(item_definition, state))
		"enhancement_stone":
			return DomainResult.ok(EnhancementStone.new(item_definition, state))
		"vehicle_chassis":
			return DomainResult.ok(VehicleChassis.new(item_definition, state))
		"vehicle_engine":
			return DomainResult.ok(VehicleEngine.new(item_definition, state))
		"energy_cannon", "missile_weapon", "rocket_weapon", "vehicle_weapon":
			return DomainResult.ok(VehicleWeapon.new(item_definition, state))
		"vehicle_equipment":
			return DomainResult.ok(VehicleEquipment.new(item_definition, state))
		"mining_arm":
			return DomainResult.ok(VehicleMiningArm.new(item_definition, state))
		"equipment":
			return DomainResult.ok(Equipment.new(item_definition, state))
		_:
			if item_definition.has("equipment_location"):
				return DomainResult.ok(VehicleEquipment.new(item_definition, state))
			return DomainResult.ok(GameItem.new(item_definition, state))


## 查询物品定义的中文显示名。
## [param definition_id] 配置表定义标识。
## 返回定义显示名；未知定义返回原标识。
func display_name(definition_id: String) -> String:
	definition_id = ItemDefinitionAliases.canonical(definition_id)
	var item_definition: Dictionary = _definitions.get(definition_id, {})
	return String(item_definition.get("display_name", definition_id))


## 返回全部可实例化定义 ID，供内容完整性测试与后续商店/任务目录连接使用。
## 执行 `definition_ids` 对应的模块操作。
func definition_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for definition_id: Variant in _definitions.keys():
		result.append(String(definition_id))
	result.sort()
	return result


## 返回单项定义的防御性副本；领域外不得修改目录内部状态。
## 执行 `definition` 对应的模块操作。
## [param definition_id] 调用方传入的 `definition_id` 参数。
func definition(definition_id: String) -> Dictionary:
	definition_id = ItemDefinitionAliases.canonical(definition_id)
	var value: Variant = _definitions.get(definition_id)
	return value.duplicate(true) if value is Dictionary else {}


## 按玩家可见名称解析稳定物品定义，供旧配方中的中文材料名接入新领域模型。
## [param display_name_value] 荣耀配方记录中的物品显示名。
## [param accepted_kinds] 可选的物品类型白名单；空数组表示接受任意类型。
## 返回首个满足类型要求的稳定定义 ID；没有匹配时返回空字符串。
## 设计：名称只在旧内容适配边界使用，背包、存档和网络协议仍只保存稳定 ID。
func definition_id_by_display_name(
	display_name_value: String,
	accepted_kinds: PackedStringArray = PackedStringArray(),
) -> String:
	var normalized := display_name_value.strip_edges()
	for definition_id: String in _definition_ids_by_display_name.get(normalized, PackedStringArray()):
		var kind := String((_definitions[definition_id] as Dictionary).get("kind", ""))
		if accepted_kinds.is_empty() or kind in accepted_kinds:
			return ItemDefinitionAliases.canonical(definition_id)
	return ""


## 为旧内容适配建立显示名到稳定 ID 的只读多值索引。
## 设计：索引保留同名定义，具体用例可用 accepted_kinds 消除歧义。
func _index_display_names() -> void:
	for definition_id: String in _definitions:
		var item_definition: Dictionary = _definitions[definition_id]
		var display_name_value := String(item_definition.get("display_name", "")).strip_edges()
		if display_name_value.is_empty():
			continue
		var ids: PackedStringArray = _definition_ids_by_display_name.get(
			display_name_value, PackedStringArray()
		)
		ids.append(definition_id)
		ids.sort()
		_definition_ids_by_display_name[display_name_value] = ids


## 读取单个玩法定义文件并合并到目录。
## [param path] Godot 资源路径。
## 返回成功或文件、JSON、重复标识错误。
func _load_gameplay_file(path: String) -> DomainResult:
	if not FileAccess.file_exists(path):
		return DomainResult.failure(&"items.catalog_missing", "item catalog is missing: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("definitions") is Array:
		return DomainResult.failure(&"items.catalog_invalid", "item catalog is invalid: %s" % path)
	for raw_definition: Variant in parsed["definitions"]:
		if not raw_definition is Dictionary:
			return DomainResult.failure(&"items.catalog_invalid", "item definition must be a dictionary")
		var item_definition: Dictionary = raw_definition.duplicate(true)
		var definition_id := String(item_definition.get("id", ""))
		var previous: Dictionary = _definitions.get(definition_id, {})
		var replaces_placeholder: bool = bool(item_definition.get("replaces_name_only", false)) \
			and previous.get("source_audit", {}).get("status", "") == "name_only" \
			and previous.get("display_name", "") == item_definition.get("source_class", "") \
			and previous.get("kind", "") == "material" and item_definition.get("kind", "") == "material"
		if definition_id.is_empty() or (_definitions.has(definition_id) and not replaces_placeholder):
			return DomainResult.failure(&"items.catalog_invalid", "item definition identity is invalid")
		_apply_equipment_contract(item_definition)
		_definitions[definition_id] = item_definition
	return DomainResult.ok()


## 读取语义化 UI 与世界表现目录。
## [param path] Godot 资源路径。
## 返回 definition_id 到表现配置的映射。
func _load_presentation_file(path: String) -> DomainResult:
	if not FileAccess.file_exists(path):
		return DomainResult.failure(&"items.presentation_missing", "item presentation catalog is missing")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("definitions") is Dictionary:
		return DomainResult.failure(&"items.presentation_invalid", "item presentation catalog is invalid")
	return DomainResult.ok((parsed["definitions"] as Dictionary).duplicate(true))


## 将旧内容表中的 kind 规范化为固定装备槽契约。
## [param item_definition] 即将进入目录的可变定义副本。
func _apply_equipment_contract(item_definition: Dictionary) -> void:
	var kind := String(item_definition.get("kind", ""))
	# 荣耀 CollecTor 基类声明 Location=1、EquipKind2=4；子类导出未展开继承字段。
	var legacy: Dictionary = item_definition.get("stats", {}).get("legacy_properties", {})
	if kind == "mining_arm" or (kind == "vehicle_equipment" and int(legacy.get("m_nEquipKind2", -1)) == 4):
		kind = "mining_arm"
		item_definition["kind"] = kind
		item_definition["equipment_location"] = 1
	# 荣耀 Repair 的 EquipKind2=3；导出器曾把维修臂归为 vehicle_weapon，不能作为炮发射。
	if kind == "repair_arm" or (kind in ["vehicle_weapon", "vehicle_equipment"] \
			and int(legacy.get("m_nEquipKind2", -1)) == 3 \
			and int(item_definition.get("equipment_location", -1)) == 1):
		kind = "repair_arm"
		item_definition["kind"] = kind
	var definition_id := String(item_definition.get("id", ""))
	if kind == "character_clothing":
		return
	var location := EquipmentSlotRegistryScript.location_for_definition(definition_id)
	if location < 0:
		location = int(item_definition.get("equipment_location", -1))
	if location < 0:
		return
	item_definition["equipment_location"] = location
	item_definition["equip_kind"] = {
		"vehicle_chassis": 0,
		"energy_cannon": 1,
		"vehicle_engine": 3,
		"mining_arm": 4,
		"repair_arm": 3,
	}.get(kind, -1)
	_normalize_legacy_vehicle_stats(item_definition)
	VehicleAttachmentPolicy.adapt(item_definition)


## 将荣耀旧客户端字段提升为充血装备模型直接消费的统一战车属性。
## [param item_definition] 已确认属于固定战车槽位的可变定义副本。
## 设计：旧字段只在目录边界出现，PlayerVehicle、战斗模块和 UI 不再各自解释 FCC 字段。
func _normalize_legacy_vehicle_stats(item_definition: Dictionary) -> void:
	var stats_value: Variant = item_definition.get("stats", {})
	if not stats_value is Dictionary:
		return
	var stats: Dictionary = stats_value
	var legacy_value: Variant = stats.get("legacy_properties", {})
	if not legacy_value is Dictionary:
		return
	var legacy: Dictionary = legacy_value
	match String(item_definition.get("kind", "")):
		"vehicle_chassis":
			_set_missing_numeric_stat(stats, "armor", legacy.get("m_narmor", 0))
			_set_missing_numeric_stat(
				stats, "working_energy_capacity", legacy.get("m_nenergy", stats.get("energy_cost", 0))
			)
			_set_missing_numeric_stat(stats, "reserve_energy_capacity", legacy.get("m_nmaxenergy", 0))
			_set_missing_numeric_stat(stats, "repair_strength", legacy.get("m_nOneRepairAttack", 0))
			_set_missing_numeric_stat(stats, "repair_energy_cost", legacy.get("m_nOneRepairEnergy", 0))
			_set_missing_numeric_stat(stats, "repair_skill_level", legacy.get("m_nRepairLevel", 0))
		"energy_cannon", "missile_weapon", "rocket_weapon", "vehicle_weapon":
			_set_missing_numeric_stat(stats, "working_energy_per_shot", legacy.get("m_nenergy", stats.get("energy_cost", 0)))
			if not stats.has("attack_interval_seconds"):
				stats["attack_interval_seconds"] = maxf(
					0.0, _numeric_value(legacy.get("m_nacttime", 800)) / 1000.0
				)


## 仅在标准字段缺失时写入旧客户端数值，避免覆盖人工确认过的配置。
## [param stats] 待补齐的统一装备属性字典。
## [param key] 统一属性名。
## [param raw_value] 旧客户端字符串或数值。
func _set_missing_numeric_stat(stats: Dictionary, key: String, raw_value: Variant) -> void:
	if not stats.has(key):
		stats[key] = _numeric_value(raw_value)


## 将 FCC 遗留的数字字符串安全转换为浮点数。
## [param raw_value] 数值或数字字符串。
## 返回可供装备模型消费的有限非负数值；非法值返回零。
func _numeric_value(raw_value: Variant) -> float:
	var result := float(raw_value)
	return maxf(0.0, result) if is_finite(result) else 0.0
