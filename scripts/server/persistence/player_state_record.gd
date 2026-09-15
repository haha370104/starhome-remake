class_name PlayerStateRecord
extends RefCounted

const InventoryStackRecordScript := preload("res://scripts/server/persistence/inventory_stack_record.gd")
const EquipmentSlotRecordScript := preload("res://scripts/server/persistence/equipment_slot_record.gd")
const CURRENT_SCHEMA_VERSION := 2

var account_id := ""
var account_name := ""
var account_status := "active"
var character_id := ""
var display_name := ""
var revision := 0
var inventory_revision := 0
var vehicle_loadout_revision := 0
var inventory_capacity := 40
var inventory_stacks: Array[InventoryStackRecord] = []
var equipment_slots: Array[EquipmentSlotRecord] = []
var currency := 0
var amethyst := 0
var character_sex := "male"
var character_level := 10
var character_profession := "新兵"
var character_faction := "龙之城"
var character_residence := "龙之城基地"
var character_description := ""
var character_max_health := 1
var character_health := 1
var character_experience := 0
var character_skills: Dictionary = {}
var quest_states: Dictionary = {}
var achievements: Dictionary = {}
var vehicle_id := ""
var vehicle_definition_id := ""
var vehicle_max_health := 0
var vehicle_health := 0
var reserve_energy_capacity := 0.0
var reserve_energy := 0.0
var working_energy_capacity := 0.0
var working_energy := 0.0
var output_power := 0.0
var map_id := ""
var map_instance_id := ""
var position := Vector2.ZERO
var facing_direction := 0
var checkpoint_id := ""


## 执行 `from_dictionary` 对应的模块操作。
## [param raw] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
static func from_dictionary(raw: Variant) -> DomainResult:
	if not raw is Dictionary:
		return DomainResult.failure(&"persistence.invalid_player_state", "player state must be a dictionary")
	if int(raw.get("schema_version", -1)) != CURRENT_SCHEMA_VERSION:
		return DomainResult.failure(&"persistence.unsupported_player_schema", "player state schema is unsupported")
	var record := PlayerStateRecord.new()
	record.account_id = String(raw.get("account_id", ""))
	record.account_name = String(raw.get("account_name", ""))
	record.account_status = String(raw.get("account_status", ""))
	record.character_id = String(raw.get("character_id", ""))
	record.display_name = String(raw.get("display_name", ""))
	record.revision = int(raw.get("revision", -1))
	record.inventory_revision = int(raw.get("inventory_revision", -1))
	record.vehicle_loadout_revision = int(raw.get("vehicle_loadout_revision", 0))
	record.inventory_capacity = int(raw.get("inventory_capacity", 0))
	record.currency = int(raw.get("currency", 0))
	record.amethyst = int(raw.get("amethyst", 0))
	record.character_sex = String(raw.get("character_sex", "male"))
	record.character_level = int(raw.get("character_level", 10))
	record.character_profession = String(raw.get("character_profession", "新兵"))
	record.character_faction = String(raw.get("character_faction", "龙之城"))
	record.character_residence = String(raw.get("character_residence", "龙之城基地"))
	if record.character_faction == "易安港":
		record.character_faction = "龙之城"
	if record.character_residence == "易安港基地":
		record.character_residence = "龙之城基地"
	record.character_description = String(raw.get("character_description", ""))
	record.character_max_health = int(raw.get("character_max_health", 0))
	record.character_health = int(raw.get("character_health", -1))
	record.character_experience = int(raw.get("character_experience", -1))
	var skills_value: Variant = raw.get("character_skills", {})
	if not skills_value is Dictionary:
		return DomainResult.failure(&"persistence.invalid_player_state", "character skills must be a dictionary")
	record.character_skills = (skills_value as Dictionary).duplicate(true)
	var quest_value: Variant = raw.get("quest_states", {})
	if not quest_value is Dictionary:
		return DomainResult.failure(&"persistence.invalid_player_state", "quest states must be a dictionary")
	record.quest_states = (quest_value as Dictionary).duplicate(true)
	var achievement_value: Variant = raw.get("achievements", {})
	if not PlayerAchievements.valid_state(achievement_value):
		return DomainResult.failure(&"persistence.invalid_player_state", "achievement state is invalid")
	record.achievements = (achievement_value as Dictionary).duplicate(true)
	record.vehicle_id = String(raw.get("vehicle_id", ""))
	record.vehicle_definition_id = String(raw.get("vehicle_definition_id", ""))
	record.vehicle_max_health = int(raw.get("vehicle_max_health", 0))
	record.vehicle_health = int(raw.get("vehicle_health", -1))
	record.reserve_energy_capacity = float(raw.get("reserve_energy_capacity", -1.0))
	record.reserve_energy = float(raw.get("reserve_energy", -1.0))
	record.working_energy_capacity = float(raw.get("working_energy_capacity", -1.0))
	record.working_energy = float(raw.get("working_energy", -1.0))
	record.output_power = float(raw.get("output_power", -1.0))
	record.map_id = String(raw.get("map_id", ""))
	record.map_instance_id = String(raw.get("map_instance_id", ""))
	record.facing_direction = int(raw.get("facing_direction", -1))
	record.checkpoint_id = String(raw.get("checkpoint_id", ""))
	var position_value: Variant = raw.get("position")
	if not position_value is Array or position_value.size() != 2:
		return DomainResult.failure(&"persistence.invalid_player_state", "player position must contain two coordinates")
	record.position = Vector2(float(position_value[0]), float(position_value[1]))
	var stack_result := record._load_inventory(raw.get("inventory_stacks"))
	if not stack_result.is_ok:
		return stack_result
	var equipment_result := record._load_equipment(raw.get("equipment_slots"))
	if not equipment_result.is_ok:
		return equipment_result
	var validation := record.validate()
	return DomainResult.ok(record) if validation.is_ok else validation


## 校验 `validate` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func validate() -> DomainResult:
	if account_id.is_empty() or account_name.is_empty() or account_status.is_empty() \
		or character_id.is_empty() or display_name.is_empty():
		return DomainResult.failure(&"persistence.invalid_player_state", "account and character identity are required")
	if revision < 0 or inventory_revision < 0 or vehicle_loadout_revision < 0 \
			or inventory_capacity <= 0 or currency < 0 or amethyst < 0:
		return DomainResult.failure(&"persistence.invalid_player_state", "aggregate revisions or capacity are invalid")
	if character_sex not in ["male", "female"] or character_level <= 0 \
			or character_profession.is_empty() or character_faction.is_empty() \
			or character_residence.is_empty():
		return DomainResult.failure(&"persistence.invalid_player_state", "character panel identity is invalid")
	if character_max_health <= 0 or character_health < 0 or character_health > character_max_health \
			or character_experience < 0:
		return DomainResult.failure(&"persistence.invalid_player_state", "character state is invalid")
	for skill_id: Variant in character_skills:
		var skill_state: Variant = character_skills[skill_id]
		if String(skill_id).is_empty() or not skill_state is Dictionary \
				or int(skill_state.get("level", -1)) < 0 \
				or int(skill_state.get("current_exp", -1)) < 0 \
				or not is_finite(float(skill_state.get("fractional_exp", -1.0))) \
				or float(skill_state.get("fractional_exp", -1.0)) < 0.0 \
				or float(skill_state.get("fractional_exp", -1.0)) >= 1.0:
			return DomainResult.failure(&"persistence.invalid_player_state", "character skill state is invalid")
	for quest_id: Variant in quest_states:
		var quest_state: Variant = quest_states[quest_id]
		if String(quest_id).is_empty() or not quest_state is Dictionary \
				or int(quest_state.get("completions", -1)) < 0 \
				or not (quest_state.get("accepted", false) is bool):
			return DomainResult.failure(&"persistence.invalid_player_state", "quest state is invalid")
	if vehicle_id.is_empty() or vehicle_definition_id.is_empty() or vehicle_max_health <= 0 \
		or vehicle_health < 0 or vehicle_health > vehicle_max_health:
		return DomainResult.failure(&"persistence.invalid_player_state", "vehicle identity or health is invalid")
	if reserve_energy_capacity < 0.0 or reserve_energy < 0.0 \
		or reserve_energy > reserve_energy_capacity or working_energy_capacity < 0.0 \
		or working_energy < 0.0 or working_energy > working_energy_capacity or output_power < 0.0:
		return DomainResult.failure(&"persistence.invalid_player_state", "vehicle energy or power state is invalid")
	if map_id.is_empty() or map_instance_id.is_empty() or not position.is_finite() \
		or facing_direction < 0 or facing_direction > 7:
		return DomainResult.failure(&"persistence.invalid_player_state", "location state is invalid")
	if inventory_stacks.size() > inventory_capacity:
		return DomainResult.failure(&"persistence.inventory_capacity_exceeded", "inventory contains more stacks than available slots")
	var used_slots: Dictionary = {}
	var stack_ids: Dictionary = {}
	for stack: InventoryStackRecord in inventory_stacks:
		if stack.slot_index >= inventory_capacity or used_slots.has(stack.slot_index) \
			or stack_ids.has(stack.stack_id):
			return DomainResult.failure(&"persistence.invalid_inventory_stack", "inventory slot or stack identity is duplicated")
		used_slots[stack.slot_index] = true
		stack_ids[stack.stack_id] = true
	var equipment_keys: Dictionary = {}
	var item_instance_ids: Dictionary = {}
	for equipment: EquipmentSlotRecord in equipment_slots:
		var slot_key := "%s:%s" % [equipment.owner_kind, equipment.slot_id]
		if equipment_keys.has(slot_key) or item_instance_ids.has(equipment.item_instance_id):
			return DomainResult.failure(&"persistence.invalid_equipment_slot", "equipment slot or item instance is duplicated")
		equipment_keys[slot_key] = true
		item_instance_ids[equipment.item_instance_id] = true
	return DomainResult.ok()


## 序列化或保存 `to_dictionary` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func to_dictionary() -> Dictionary:
	var serialized_stacks: Array[Dictionary] = []
	for stack: InventoryStackRecord in inventory_stacks:
		serialized_stacks.append(stack.to_dictionary())
	var serialized_equipment: Array[Dictionary] = []
	for equipment: EquipmentSlotRecord in equipment_slots:
		serialized_equipment.append(equipment.to_dictionary())
	return {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"account_id": account_id,
		"account_name": account_name,
		"account_status": account_status,
		"character_id": character_id,
		"display_name": display_name,
		"revision": revision,
		"inventory_revision": inventory_revision,
		"vehicle_loadout_revision": vehicle_loadout_revision,
		"inventory_capacity": inventory_capacity,
		"currency": currency,
		"amethyst": amethyst,
		"character_sex": character_sex,
		"character_level": character_level,
		"character_profession": character_profession,
		"character_faction": character_faction,
		"character_residence": character_residence,
		"character_description": character_description,
		"inventory_stacks": serialized_stacks,
		"equipment_slots": serialized_equipment,
		"character_max_health": character_max_health,
		"character_health": character_health,
		"character_experience": character_experience,
		"character_skills": character_skills.duplicate(true),
		"quest_states": quest_states.duplicate(true),
		"achievements": achievements.duplicate(true),
		"vehicle_id": vehicle_id,
		"vehicle_definition_id": vehicle_definition_id,
		"vehicle_max_health": vehicle_max_health,
		"vehicle_health": vehicle_health,
		"reserve_energy_capacity": reserve_energy_capacity,
		"reserve_energy": reserve_energy,
		"working_energy_capacity": working_energy_capacity,
		"working_energy": working_energy,
		"output_power": output_power,
		"map_id": map_id,
		"map_instance_id": map_instance_id,
		"position": [position.x, position.y],
		"facing_direction": facing_direction,
		"checkpoint_id": checkpoint_id,
	}


## 执行 `duplicate_record` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func duplicate_record() -> PlayerStateRecord:
	return PlayerStateRecord.from_dictionary(to_dictionary()).value


## 执行 `load_inventory` 对应的模块操作。
## [param raw_stacks] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _load_inventory(raw_stacks: Variant) -> DomainResult:
	if not raw_stacks is Array:
		return DomainResult.failure(&"persistence.invalid_player_state", "inventory stacks must be an array")
	for raw_stack: Variant in raw_stacks:
		var result := InventoryStackRecordScript.from_dictionary(raw_stack)
		if not result.is_ok:
			return result
		inventory_stacks.append(result.value)
	return DomainResult.ok()


## 执行 `load_equipment` 对应的模块操作。
## [param raw_equipment] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _load_equipment(raw_equipment: Variant) -> DomainResult:
	if not raw_equipment is Array:
		return DomainResult.failure(&"persistence.invalid_player_state", "equipment slots must be an array")
	for raw_slot: Variant in raw_equipment:
		var result := EquipmentSlotRecordScript.from_dictionary(raw_slot)
		if not result.is_ok:
			return result
		equipment_slots.append(result.value)
	return DomainResult.ok()
