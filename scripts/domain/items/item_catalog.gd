class_name ItemCatalog
extends RefCounted

const EquipmentSlotRegistryScript := preload("res://scripts/domain/equipment/equipment_slot_registry.gd")

const GAMEPLAY_PATHS := [
	"res://data/gameplay/austin_glens_items_v1.json",
	"res://data/gameplay/crystal_source_items_v1.json",
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
	"res://data/gameplay/vehicle_workshop_items_v1.json",
	"res://data/gameplay/equipment_processing_items_v1.json",
	"res://data/gameplay/equipment_maintenance_items_v1.json",
	"res://data/gameplay/extra_attribute_items_v1.json",
	"res://data/gameplay/equipment_strengthening_items_v1.json",
	"res://data/gameplay/armor_refinement_items_v1.json",
	"res://data/gameplay/clothing_improvement_items_v1.json",
	"res://data/gameplay/equipment_memory_items_v1.json",
	"res://data/gameplay/equipment_dismantle_materials_v1.json",
	"res://data/gameplay/equipment_forging_items_v1.json",
]
const PRESENTATION_PATHS := [
	"res://data/presentation/crystal_source_materials_v1.json",
	"res://data/presentation/player_equipment_v1.json",
	"res://data/presentation/ground_loot_v1.json",
	"res://data/presentation/recovered_equipment_v1.json",
]

var _definitions: Dictionary = {}
var _definition_ids_by_display_name: Dictionary = {}
var socket_rules: VehicleSocketRules
var processing_rules: EquipmentProcessingRules
var maintenance_rules: EquipmentMaintenanceRules
var extra_attribute_rules: ExtraAttributeRules
var strengthening_rules: EquipmentStrengtheningRules
var armor_refinement_rules: ArmorRefinementRules
var clothing_improvement_rules: ClothingImprovementRules
var memory_rules: EquipmentMemoryRules
var quality_rules: EquipmentQualityRules
var dismantle_rules: EquipmentDismantleRules
var forging_rules: EquipmentForgingRules
var generator_rules: GeneratorRules
var crystal_source_rules: CrystalSourceRules
var austin_rules: AustinGlensRules


## 读取所有当前启用的物品定义和语义化表现目录。
## 返回加载成功的目录实例或具体格式错误。
## 设计：目录负责“配置到具体类型”的组装；领域对象本身不读取文件，也不知道服务端或客户端。
func initialize() -> DomainResult:
	_definitions.clear()
	_definition_ids_by_display_name.clear()
	var austin_data := JsonConfigLoader.load_dictionary("res://data/gameplay/austin_glens_rules_v1.json")
	if not austin_data.is_ok: return austin_data
	var austin_result := AustinGlensRules.from_dictionary(austin_data.value)
	if not austin_result.is_ok: return austin_result
	austin_rules = austin_result.value
	var crystal_data := JsonConfigLoader.load_dictionary("res://data/gameplay/crystal_source_rules_v1.json")
	if not crystal_data.is_ok: return crystal_data
	var crystal_rules := CrystalSourceRules.from_dictionary(crystal_data.value)
	if not crystal_rules.is_ok: return crystal_rules
	crystal_source_rules = crystal_rules.value
	for path: String in GAMEPLAY_PATHS:
		var loaded := _load_gameplay_file(path)
		if not loaded.is_ok:
			return loaded
	for id: String in crystal_source_rules.profiles:
		var profile := crystal_source_rules.profiles[id]
		for referenced_id: String in [id, profile.crystal_id, profile.source_id, profile.advanced_source_id]:
			if not _definitions.has(referenced_id): return DomainResult.failure(&"crystal_source.catalog", "晶源体引用了不存在的装备或材料")
	for id: String in crystal_source_rules.offers:
		if not _definitions.has(id): return DomainResult.failure(&"crystal_source.catalog", "晶源体商品不存在")
	for referenced_id: String in austin_rules.profiles.keys() + austin_rules.runes.keys() + austin_rules.materials.values() + austin_rules.offers.keys():
		if not _definitions.has(referenced_id): return DomainResult.failure(&"austin.catalog", "奥斯格兰引用了不存在的物品")
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
	var socket_data := JsonConfigLoader.load_dictionary("res://data/gameplay/vehicle_socket_rules_v1.json")
	if not socket_data.is_ok:
		return socket_data
	var socket_result := VehicleSocketRules.from_dictionary(socket_data.value)
	if not socket_result.is_ok:
		return socket_result
	socket_rules = socket_result.value
	var processing_data := JsonConfigLoader.load_dictionary("res://data/gameplay/equipment_processing_rules_v1.json")
	if not processing_data.is_ok:
		return processing_data
	var processing_result := EquipmentProcessingRules.from_dictionary(processing_data.value)
	if not processing_result.is_ok:
		return processing_result
	processing_rules = processing_result.value
	var maintenance_data := JsonConfigLoader.load_dictionary("res://data/gameplay/equipment_maintenance_rules_v1.json")
	if not maintenance_data.is_ok:
		return maintenance_data
	var maintenance_result := EquipmentMaintenanceRules.from_dictionary(maintenance_data.value)
	if not maintenance_result.is_ok:
		return maintenance_result
	maintenance_rules = maintenance_result.value
	var extra_data := JsonConfigLoader.load_dictionary("res://data/gameplay/extra_attribute_rules_v1.json")
	if not extra_data.is_ok: return extra_data
	var extra_result := ExtraAttributeRules.from_dictionary(extra_data.value)
	if not extra_result.is_ok: return extra_result
	extra_attribute_rules = extra_result.value
	var strengthening_data := JsonConfigLoader.load_dictionary("res://data/gameplay/equipment_strengthening_rules_v1.json")
	if not strengthening_data.is_ok: return strengthening_data
	var strengthening_result := EquipmentStrengtheningRules.from_dictionary(strengthening_data.value)
	if not strengthening_result.is_ok: return strengthening_result
	strengthening_rules = strengthening_result.value
	var armor_data := JsonConfigLoader.load_dictionary("res://data/gameplay/armor_refinement_rules_v1.json")
	if not armor_data.is_ok: return armor_data
	var armor_result := ArmorRefinementRules.from_dictionary(armor_data.value)
	if not armor_result.is_ok: return armor_result
	armor_refinement_rules = armor_result.value
	var clothing_data := JsonConfigLoader.load_dictionary("res://data/gameplay/clothing_improvement_rules_v1.json")
	if not clothing_data.is_ok: return clothing_data
	var clothing_result := ClothingImprovementRules.from_dictionary(clothing_data.value)
	if not clothing_result.is_ok: return clothing_result
	clothing_improvement_rules = clothing_result.value
	var memory_data := JsonConfigLoader.load_dictionary("res://data/gameplay/equipment_memory_rules_v1.json")
	if not memory_data.is_ok: return memory_data
	var memory_result := EquipmentMemoryRules.from_dictionary(memory_data.value)
	if not memory_result.is_ok: return memory_result
	memory_rules = memory_result.value
	var quality_data := JsonConfigLoader.load_dictionary("res://data/gameplay/equipment_quality_rules_v1.json")
	if not quality_data.is_ok: return quality_data
	var quality_result := EquipmentQualityRules.from_dictionary(quality_data.value)
	if not quality_result.is_ok: return quality_result
	quality_rules = quality_result.value
	var forging_data := JsonConfigLoader.load_dictionary("res://data/gameplay/equipment_forging_rules_v1.json")
	if not forging_data.is_ok: return forging_data
	var forging_result := EquipmentForgingRules.from_dictionary(forging_data.value)
	if not forging_result.is_ok: return forging_result
	forging_rules = forging_result.value
	var generator_data := JsonConfigLoader.load_dictionary("res://data/gameplay/generator_rules_v1.json")
	if not generator_data.is_ok: return generator_data
	var generator_result := GeneratorRules.from_dictionary(generator_data.value)
	if not generator_result.is_ok: return generator_result
	generator_rules = generator_result.value
	for id: String in generator_rules.profiles:
		if not _definitions.has(id) or _definitions[id].get("attachment_family", "") != "generator":
			return DomainResult.failure(&"generator.rules", "发生器规则引用未装配的物品类型")
		_definitions[id]["display_name"] = generator_rules.profiles[id].label
	var dismantle_data := JsonConfigLoader.load_dictionary("res://data/gameplay/equipment_dismantle_rules_v1.json")
	if not dismantle_data.is_ok: return dismantle_data
	var dismantle_result := EquipmentDismantleRules.from_dictionary(dismantle_data.value, self)
	if not dismantle_result.is_ok: return dismantle_result
	dismantle_rules = dismantle_result.value
	for id: String in clothing_improvement_rules.slots:
		var slot: String = clothing_improvement_rules.slots[id]
		if slot == "head" and _definitions[id].get("character_slot") == "upper_body":
			_definitions[id]["legacy_character_slot"] = "upper_body"
		_definitions[id]["character_slot"] = slot
	for profile: ArmorRefinementRules.Profile in armor_refinement_rules.profiles.values():
		_definitions[profile.definition_id]["display_name"] = profile.display_name
	var ammunition_data := JsonConfigLoader.load_dictionary("res://data/gameplay/equipment_ammunition_rules_v1.json")
	if not ammunition_data.is_ok: return ammunition_data
	for row: Dictionary in ammunition_data.value.get("equipment", []):
		if not _definitions.has(row.definition_id) or int(row.capacity) <= 0 or int(row.unit_price) <= 0:
			return DomainResult.failure(&"ammunition.rules_invalid", "弹药定义无效")
		_definitions[row.definition_id].stats["ammunition_capacity"] = int(row.capacity)
		_definitions[row.definition_id].stats["ammunition_unit_price"] = int(row.unit_price)
	_index_display_names()
	return DomainResult.ok(self)


## 按定义与实例状态创建具体业务类型的物品。
## [param definition_id] 配置表定义标识。
## [param state] 存档中的实例状态。
## 返回服装、战车底盘、引擎、武器、采掘臂、通用装备或普通物品的具体实例。
func create(definition_id: String, state: Dictionary) -> DomainResult:
	var crystal_source := CrystalSourceGrowth.restore(state.get("crystal_source", {}))
	var austin := AustinGlensGrowth.restore(state.get("austin_glens", {}))
	if not austin.is_ok: return austin
	var austin_profile: AustinGlensRules.Profile = austin_rules.profiles.get(ItemDefinitionAliases.canonical(definition_id))
	var austin_check := (austin.value as AustinGlensGrowth).validate_for(austin_profile, austin_rules)
	if not austin_check.is_ok: return austin_check
	if not crystal_source.is_ok: return crystal_source
	var crystal_profile: CrystalSourceRules.Profile = crystal_source_rules.profiles.get(ItemDefinitionAliases.canonical(definition_id))
	var crystal_check := (crystal_source.value as CrystalSourceGrowth).validate_for(crystal_profile, crystal_source_rules)
	if not crystal_check.is_ok: return crystal_check
	var source_cracks: Variant = state.get("crystal_source_cracks", 0)
	if not CrystalSourceRules.integer(source_cracks, 0, 3) \
		or (source_cracks != 0 and not crystal_source_rules.cores.has(ItemDefinitionAliases.canonical(definition_id))):
		return DomainResult.failure(&"crystal_source.cracks", "非晶源核物品或晶源核裂纹无效")
	var quality := EquipmentQuality.restore(state.get("equipment_quality", {}))
	if not quality.is_ok: return quality
	var quality_check := (quality.value as EquipmentQuality).validate_for(quality_rules.profiles.get(ItemDefinitionAliases.canonical(definition_id)))
	if not quality_check.is_ok: return quality_check
	var memory := EquipmentMemory.restore(state.get("equipment_memory", {}))
	if not memory.is_ok: return memory
	var improved := ClothingImprovement.restore(state.get("clothing_improvement", {}))
	if not improved.is_ok: return improved
	var improved_check := (improved.value as ClothingImprovement).validate_for(ItemDefinitionAliases.canonical(definition_id), clothing_improvement_rules)
	if not improved_check.is_ok: return improved_check
	var stars := EquipmentStrengthening.restore(state.get("strengthening", {}))
	if not stars.is_ok: return stars
	var stars_check := (stars.value as EquipmentStrengthening).validate_for(strengthening_rules.profiles.get(ItemDefinitionAliases.canonical(definition_id)))
	if not stars_check.is_ok: return stars_check
	var extra := ExtraAttributes.restore(state.get("extra_attributes", {}))
	if not extra.is_ok: return extra
	var extra_check := (extra.value as ExtraAttributes).validate_for(ItemDefinitionAliases.canonical(definition_id), extra_attribute_rules)
	if not extra_check.is_ok: return extra_check
	var rounds := WeaponMagazine.restore(state.get("magazine", {}))
	if not rounds.is_ok: return rounds
	var used := EquipmentUsage.restore(state.get("usage", {}))
	if not used.is_ok:
		return used
	var forged := EquipmentForging.restore(state.get("forging", {}))
	if not forged.is_ok: return forged
	var forging: EquipmentForging = forged.value
	var forging_check := forging.validate_for(forging_rules.profiles.get(ItemDefinitionAliases.canonical(definition_id)))
	if not forging_check.is_ok: return forging_check
	var processed := EquipmentProcessing.restore(state.get("processing", {}))
	if not processed.is_ok:
		return processed
	var processing_check := (processed.value as EquipmentProcessing).validate_for(forging.expanded_processing(processing_rules.profile(ItemDefinitionAliases.canonical(definition_id)), forging_rules))
	if not processing_check.is_ok:
		return processing_check
	var sockets_result := VehicleSockets.restore(state.get("vehicle_sockets", {}))
	if not sockets_result.is_ok:
		return sockets_result
	var cracks := VehicleCrystal.restore_cracks(state.get("crystal_cracks", 0))
	if not cracks.is_ok:
		return cracks
	var result := _create_item(definition_id, state)
	if not result.is_ok:
		return result
	var item: GameItem = result.value
	var memory_check := (memory.value as EquipmentMemory).validate_for(item.module_type if item is EquipmentMemoryModule else 0, self)
	if not memory_check.is_ok: return memory_check
	if item is Clothing:
		item.improvement_rules = clothing_improvement_rules
	if item is Equipment:
		item.forging_rules = forging_rules
		item.forging_profile = forging_rules.profiles.get(item.definition_id)
		item.quality_profile = quality_rules.profiles.get(item.definition_id)
		item.dismantle_eligible = dismantle_rules.profiles.has(item.definition_id)
		item.memory_profile = memory_rules.profiles.get(item.definition_id)
		item.armor_refinement_profile = armor_refinement_rules.profiles.get(item.definition_id)
		item.extra_attribute_rules = extra_attribute_rules
		item.strengthening_rules = strengthening_rules
		item.strengthening_profile = strengthening_rules.profiles.get(item.definition_id)
		item.refresh_processed_stats()
		var ammunition_check := (rounds.value as WeaponMagazine).bind_capacity(item.ammunition_capacity())
		if not ammunition_check.is_ok: return ammunition_check
		item.magazine = rounds.value
		item.processing_rules = processing_rules
		item.maintenance_profile = maintenance_rules.profile(item.definition_id)
	if not item is VehicleCrystal and cracks.value != 0:
		return DomainResult.failure(&"sockets.invalid_state", "非晶石物品不能带有裂纹")
	var checked := (sockets_result.value as VehicleSockets).validate_for(
		socket_rules.profile(item.definition_id) if item is VehicleEquipment else null, socket_rules)
	if not checked.is_ok:
		return checked
	if item is VehicleEquipment:
		item.austin_glens = austin.value
		item.austin_profile = austin_profile
		item.austin_rules = austin_rules
		for slot: AustinGlensGrowth.Slot in item.austin_glens.slots:
			item.bound = item.bound or slot.bound
		item.crystal_source = crystal_source.value
		item.crystal_source_profile = crystal_profile
		item.crystal_source_rules = crystal_source_rules
		if crystal_profile != null:
			item.bound = item.bound or crystal_profile.bound
			for slot: CrystalSourceGrowth.Slot in item.crystal_source.slots:
				item.bound = item.bound or slot.bound
		item.generator_profile = generator_rules.profiles.get(item.definition_id)
		item.sockets = sockets_result.value
		item.socket_rules = socket_rules
	return result


## 创建具体物品；额外实例状态由公开工厂统一验证。
## [param definition_id] 稳定定义。
## [param state] 实例字段。
## 返回物品或定义错误。
func _create_item(definition_id: String, state: Dictionary) -> DomainResult:
	definition_id = ItemDefinitionAliases.canonical(definition_id)
	if not _definitions.has(definition_id):
		return DomainResult.failure(&"items.definition_missing", "item definition does not exist")
	var item_definition: Dictionary = _definitions[definition_id].duplicate(true)
	var kind := String(item_definition.get("kind", ""))
	if crystal_source_rules.cores.has(definition_id):
		var core := CrystalSourceCore.new(item_definition, state)
		core.profile = crystal_source_rules.cores[definition_id]
		return DomainResult.ok(core)
	var extra_material := extra_attribute_rules.material(definition_id)
	if extra_material != null:
		item_definition["extra_attribute_channel"] = extra_material.id
		return DomainResult.ok(ExtraAttributeMaterial.new(item_definition, state))
	var maintenance_tool := maintenance_rules.repair_tool(definition_id)
	if maintenance_tool != null:
		item_definition["maintenance_tool"] = {"scope": maintenance_tool.scope, "kind": maintenance_tool.kind, "amount": maintenance_tool.amount}
		return DomainResult.ok(EquipmentMaintenanceTool.new(item_definition, state))
	var processing_material := processing_rules.material(definition_id)
	if processing_material != null:
		item_definition["processing_material"] = {"attribute": processing_material.attribute, "points": processing_material.points}
		return DomainResult.ok(EquipmentProcessingMaterial.new(item_definition, state))
	if socket_rules.crystal(definition_id) != null:
		return DomainResult.ok(VehicleCrystal.new(item_definition, state))
	if item_definition.has("use_rule"):
		return DomainResult.ok(ConsumableItem.new(item_definition, state))
	match kind:
		"equipment_forging_material":
			return DomainResult.ok(EquipmentForgingMaterial.new(item_definition, state))
		"equipment_memory_module":
			return DomainResult.ok(EquipmentMemoryModule.new(item_definition, state))
		"clothing_improvement_material":
			return DomainResult.ok(ClothingImprovementMaterial.new(item_definition, state))
		"armor_refinement_material":
			return DomainResult.ok(ArmorRefinementMaterial.new(item_definition, state))
		"equipment_strengthening_material":
			return DomainResult.ok(EquipmentStrengtheningMaterial.new(item_definition, state))
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
	if austin_rules.profiles.has(definition_id):
		var profile := austin_rules.profiles[definition_id]
		item_definition["equipment_location"] = profile.location
		item_definition["allowed_locations"] = [profile.location]
	if crystal_source_rules.profiles.has(definition_id):
		var profile := crystal_source_rules.profiles[definition_id]
		item_definition["equipment_location"] = profile.location
		item_definition["allowed_locations"] = [profile.location]
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
	_set_missing_numeric_stat(stats, "armor", legacy.get("m_narmor", 0))
	match String(item_definition.get("kind", "")):
		"vehicle_chassis":
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
