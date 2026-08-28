class_name ItemCatalog
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const EquipmentSlotRegistryScript := preload("res://scripts/domain/equipment/equipment_slot_registry.gd")

const GAMEPLAY_PATHS := [
	"res://data/gameplay/stage3/starter_loadout_v1.json",
	"res://data/gameplay/character_items_v1.json",
	"res://data/gameplay/material_items_v1.json",
]
const PRESENTATION_PATH := "res://data/presentation/player_equipment_v1.json"

var _definitions: Dictionary = {}


## 读取所有当前启用的物品定义和语义化表现目录。
## 返回加载成功的目录实例或具体格式错误。
## 设计：目录负责“配置到具体类型”的组装；领域对象本身不读取文件，也不知道服务端或客户端。
func initialize() -> DomainResult:
	_definitions.clear()
	for path: String in GAMEPLAY_PATHS:
		var loaded := _load_gameplay_file(path)
		if not loaded.is_ok:
			return loaded
	var presentation_result := _load_presentation_file(PRESENTATION_PATH)
	if not presentation_result.is_ok:
		return presentation_result
	for definition_id: Variant in presentation_result.value:
		if not _definitions.has(String(definition_id)):
			return DomainResult.failure(&"items.presentation_orphan", "presentation references unknown item")
		_definitions[String(definition_id)]["presentation"] = \
			presentation_result.value[definition_id].duplicate(true)
	return DomainResult.ok(self)


## 按定义与实例状态创建具体业务类型的物品。
## [param definition_id] 配置表定义标识。
## [param state] 存档中的实例状态。
## 返回 Clothing、VehicleChassis、VehicleEngine、VehicleWeapon、VehicleEquipment 或 GameItem。
func create(definition_id: String, state: Dictionary) -> DomainResult:
	if not _definitions.has(definition_id):
		return DomainResult.failure(&"items.definition_missing", "item definition does not exist")
	var definition: Dictionary = _definitions[definition_id].duplicate(true)
	var kind := String(definition.get("kind", ""))
	match kind:
		"character_clothing":
			return DomainResult.ok(Clothing.new(definition, state))
		"vehicle_chassis":
			return DomainResult.ok(VehicleChassis.new(definition, state))
		"vehicle_engine":
			return DomainResult.ok(VehicleEngine.new(definition, state))
		"energy_cannon", "missile_weapon", "rocket_weapon":
			return DomainResult.ok(VehicleWeapon.new(definition, state))
		_:
			if definition.has("equipment_location"):
				return DomainResult.ok(VehicleEquipment.new(definition, state))
			return DomainResult.ok(GameItem.new(definition, state))


## 查询物品定义的中文显示名。
## [param definition_id] 配置表定义标识。
## 返回定义显示名；未知定义返回原标识。
func display_name(definition_id: String) -> String:
	var definition: Dictionary = _definitions.get(definition_id, {})
	return String(definition.get("display_name", definition_id))


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
		var definition: Dictionary = raw_definition.duplicate(true)
		var definition_id := String(definition.get("id", ""))
		if definition_id.is_empty() or _definitions.has(definition_id):
			return DomainResult.failure(&"items.catalog_invalid", "item definition identity is invalid")
		_apply_equipment_contract(definition)
		_definitions[definition_id] = definition
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
## [param definition] 即将进入目录的可变定义副本。
func _apply_equipment_contract(definition: Dictionary) -> void:
	var kind := String(definition.get("kind", ""))
	var definition_id := String(definition.get("id", ""))
	if kind == "character_clothing":
		return
	var location := EquipmentSlotRegistryScript.location_for_definition(definition_id)
	if location < 0:
		return
	definition["equipment_location"] = location
	definition["equip_kind"] = {
		"vehicle_chassis": 0,
		"energy_cannon": 1,
		"vehicle_engine": 3,
	}.get(kind, -1)
