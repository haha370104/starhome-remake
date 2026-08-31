class_name ItemCatalog
extends RefCounted

const EquipmentSlotRegistryScript := preload("res://scripts/domain/equipment/equipment_slot_registry.gd")

const GAMEPLAY_PATHS := [
	"res://data/gameplay/stage3/starter_loadout_v1.json",
	"res://data/gameplay/character_items_v1.json",
	"res://data/gameplay/material_items_v1.json",
	"res://data/gameplay/glory/glory_items_v1.json",
]
const PRESENTATION_PATHS := [
	"res://data/presentation/player_equipment_v1.json",
	"res://data/presentation/ground_loot_v1.json",
]

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
	return DomainResult.ok(self)


## 按定义与实例状态创建具体业务类型的物品。
## [param definition_id] 配置表定义标识。
## [param state] 存档中的实例状态。
## 返回 Clothing、VehicleChassis、VehicleEngine、VehicleWeapon、VehicleEquipment 或 GameItem。
func create(definition_id: String, state: Dictionary) -> DomainResult:
	if not _definitions.has(definition_id):
		return DomainResult.failure(&"items.definition_missing", "item definition does not exist")
	var item_definition: Dictionary = _definitions[definition_id].duplicate(true)
	var kind := String(item_definition.get("kind", ""))
	match kind:
		"character_clothing":
			return DomainResult.ok(Clothing.new(item_definition, state))
		"vehicle_chassis":
			return DomainResult.ok(VehicleChassis.new(item_definition, state))
		"vehicle_engine":
			return DomainResult.ok(VehicleEngine.new(item_definition, state))
		"energy_cannon", "missile_weapon", "rocket_weapon", "vehicle_weapon":
			return DomainResult.ok(VehicleWeapon.new(item_definition, state))
		"vehicle_equipment":
			return DomainResult.ok(VehicleEquipment.new(item_definition, state))
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
	var value: Variant = _definitions.get(definition_id)
	return value.duplicate(true) if value is Dictionary else {}


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
		if definition_id.is_empty() or _definitions.has(definition_id):
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
	var definition_id := String(item_definition.get("id", ""))
	if kind == "character_clothing":
		return
	var location := EquipmentSlotRegistryScript.location_for_definition(definition_id)
	if location < 0:
		return
	item_definition["equipment_location"] = location
	item_definition["equip_kind"] = {
		"vehicle_chassis": 0,
		"energy_cannon": 1,
		"vehicle_engine": 3,
	}.get(kind, -1)
