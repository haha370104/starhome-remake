class_name PlayerStateRecord
extends RefCounted

const InventoryStackRecordScript := preload("res://scripts/server/persistence/inventory_stack_record.gd")
const EquipmentSlotRecordScript := preload("res://scripts/server/persistence/equipment_slot_record.gd")
const CURRENT_SCHEMA_VERSION := 3
const CURRENT_FIELDS := [
	"schema_version", "account_id", "account_name", "account_status", "character_id", "display_name",
	"revision", "inventory_revision", "vehicle_loadout_revision", "inventory_capacity", "currency", "amethyst",
	"character_sex", "character_level", "character_profession", "character_faction", "character_residence",
	"character_description", "inventory_stacks", "equipment_slots", "character_max_health", "character_health",
	"character_experience", "character_skills", "quest_states", "achievements", "daily_activities", "food_status",
	"production", "central", "vehicle_presets", "vehicle_id", "vehicle_definition_id", "vehicle_max_health",
	"vehicle_health", "reserve_energy_capacity", "reserve_energy", "working_energy_capacity", "working_energy",
	"output_power", "map_id", "map_instance_id", "position", "facing_direction", "checkpoint_id", "warehouse",
	"friend_ids", "enemy_ids", "mailbox",
]

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
var warehouse := PersonalWarehouseRecord.new()
var production := ProductionQueue.new()
var central := PlayerCentralController.new()
var vehicle_presets := VehicleLoadoutPresets.new()
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
var achievements: Dictionary = {"counters": {}, "receipts": {}}
var daily_activities: Dictionary = DailyActivityJournal.new().to_dictionary()
var food_status: Dictionary = FoodStatus.new().to_dictionary()
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
var friend_ids: Array[String] = []
var enemy_ids: Array[String] = []
var mailbox: Array[Dictionary] = []


## 执行 `from_dictionary` 对应的模块操作。
## [param raw] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
static func from_dictionary(raw: Variant) -> DomainResult:
	return _from_dictionary(raw)


static func _from_dictionary(raw: Variant, shared_warehouse: PersonalWarehouseRecord = null) -> DomainResult:
	if not raw is Dictionary:
		return DomainResult.failure(&"persistence.invalid_player_state", "player state must be a dictionary")
	var expected_fields: Array = CURRENT_FIELDS.duplicate()
	if shared_warehouse != null:
		expected_fields.erase("warehouse")
	var optional_fields := ["friend_ids", "enemy_ids", "mailbox"]
	if raw.size() > expected_fields.size():
		return DomainResult.failure(&"persistence.invalid_player_state", "player state fields do not match the current schema")
	for field: String in expected_fields:
		if not raw.has(field) and field not in optional_fields:
			return DomainResult.failure(&"persistence.invalid_player_state", "player state is missing a current-schema field")
	for field: Variant in raw:
		if String(field) not in expected_fields:
			return DomainResult.failure(&"persistence.invalid_player_state", "player state contains an unknown field")
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
	record.character_description = String(raw.get("character_description", ""))
	record.character_max_health = int(raw.get("character_max_health", 0))
	record.character_health = int(raw.get("character_health", -1))
	record.character_experience = int(raw.get("character_experience", -1))
	var skills_value: Variant = raw.get("character_skills", {})
	if not skills_value is Dictionary:
		return DomainResult.failure(&"persistence.invalid_player_state", "character skills must be a dictionary")
	for skill_id: Variant in skills_value:
		if not skills_value[skill_id] is Dictionary:
			return DomainResult.failure(&"persistence.invalid_player_state", "skill state must be a dictionary")
	record.character_skills = (skills_value as Dictionary).duplicate(true)
	var quest_value: Variant = raw.get("quest_states", {})
	if not quest_value is Dictionary:
		return DomainResult.failure(&"persistence.invalid_player_state", "quest states must be a dictionary")
	record.quest_states = (quest_value as Dictionary).duplicate(true)
	var achievement_value: Variant = raw.get("achievements", {})
	if not PlayerAchievements.valid_persisted_state(achievement_value):
		return DomainResult.failure(&"persistence.invalid_player_state", "achievement state is invalid")
	record.achievements = (achievement_value as Dictionary).duplicate(true)
	var food_value: Variant = raw.get("food_status", {})
	if not FoodStatus.valid_state(food_value):
		return DomainResult.failure(&"persistence.invalid_player_state", "food status is invalid")
	record.food_status = food_value.duplicate(true)
	var daily_value: Variant = raw.get("daily_activities", {})
	if not DailyActivityJournal.valid_state(daily_value):
		return DomainResult.failure(&"persistence.invalid_player_state", "daily activity state is invalid")
	record.daily_activities = DailyActivityJournal.new(daily_value).to_dictionary()
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
	var friend_result := _relation_ids(raw.get("friend_ids", []), "friend_ids")
	if not friend_result.is_ok: return friend_result
	record.friend_ids = friend_result.value
	var enemy_result := _relation_ids(raw.get("enemy_ids", []), "enemy_ids")
	if not enemy_result.is_ok: return enemy_result
	record.enemy_ids = enemy_result.value
	var mailbox_result := _mailbox(raw.get("mailbox", []), record.character_id)
	if not mailbox_result.is_ok: return mailbox_result
	record.mailbox = mailbox_result.value
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
	if raw.has("warehouse"):
		var warehouse_result := PersonalWarehouseRecord.from_dictionary(raw.warehouse)
		if not warehouse_result.is_ok: return warehouse_result
		record.warehouse = warehouse_result.value
	elif shared_warehouse != null:
		record.warehouse = shared_warehouse
	else:
		return DomainResult.failure(&"persistence.invalid_player_state", "warehouse state is required")
	var production_result := ProductionQueue.restore(raw.get("production", {}))
	if not production_result.is_ok: return production_result
	record.production = production_result.value
	var central_result := PlayerCentralController.restore(raw.get("central", {}))
	if not central_result.is_ok: return central_result
	record.central = central_result.value
	var preset_result := VehicleLoadoutPresets.restore(raw.get("vehicle_presets", {}))
	if not preset_result.is_ok: return preset_result
	record.vehicle_presets = preset_result.value
	var validation := record.validate()
	return DomainResult.ok(record) if validation.is_ok else validation


## 校验 `validate` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func validate() -> DomainResult:
	if central == null or not PlayerCentralController.restore(central.to_dictionary()).is_ok:
		return DomainResult.failure(&"central.state", "中枢角色存档无效")
	if vehicle_presets == null or not VehicleLoadoutPresets.restore(vehicle_presets.to_dictionary()).is_ok:
		return DomainResult.failure(&"persistence.invalid_player_state", "vehicle presets are invalid")
	if production == null or not ProductionQueue.restore(production.to_dictionary()).is_ok:
		return DomainResult.failure(&"persistence.invalid_player_state", "production state is invalid")
	if not FoodStatus.valid_state(food_status):
		return DomainResult.failure(&"persistence.invalid_player_state", "food status is invalid")
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
	var relation_ids: Dictionary = {}
	for relation_id: String in friend_ids + enemy_ids:
		if relation_id.is_empty() or relation_id == character_id or relation_ids.has(relation_id):
			return DomainResult.failure(&"persistence.invalid_player_state", "social relation identities are invalid")
		relation_ids[relation_id] = true
	var mailbox_result := _mailbox(mailbox, character_id)
	if not mailbox_result.is_ok:
		return mailbox_result
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
		if equipment_keys.has(slot_key) or item_instance_ids.has(equipment.item_instance_id) or stack_ids.has(equipment.item_instance_id):
			return DomainResult.failure(&"persistence.invalid_equipment_slot", "equipment slot or item instance is duplicated")
		equipment_keys[slot_key] = true
		item_instance_ids[equipment.item_instance_id] = true
	return warehouse.validate_disjoint(stack_ids, item_instance_ids)


## 序列化玩家事实，磁盘保存包含仓库；内部快照复制可共用不可变仓库记录。
## [param include_warehouse] 是否展开仓库物品用于JSON序列化。
## 返回独立玩家字典。
func to_dictionary(include_warehouse: bool = true) -> Dictionary:
	var serialized_stacks: Array[Dictionary] = []
	for stack: InventoryStackRecord in inventory_stacks:
		serialized_stacks.append(stack.to_dictionary())
	var serialized_equipment: Array[Dictionary] = []
	for equipment: EquipmentSlotRecord in equipment_slots:
		serialized_equipment.append(equipment.to_dictionary())
	var state := {
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
		"daily_activities": daily_activities.duplicate(true),
		"food_status": food_status.duplicate(true),
		"production": production.to_dictionary(),
		"central": central.to_dictionary(),
		"vehicle_presets": vehicle_presets.to_dictionary(),
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
		"friend_ids": friend_ids.duplicate(),
		"enemy_ids": enemy_ids.duplicate(),
		"mailbox": mailbox.duplicate(true),
	}
	if include_warehouse: state["warehouse"] = warehouse.to_dictionary()
	return state


## 复制可变玩家状态，并共享封装后的不可变仓库快照，避免日常事务展开数百件物品。
## 返回独立玩家记录；仓库实际存取生成新快照，不改写此处共享的旧记录。
func duplicate_record() -> PlayerStateRecord:
	var duplicated := _from_dictionary(to_dictionary(false), warehouse)
	if not duplicated.is_ok: return null
	var copied: PlayerStateRecord = duplicated.value
	return copied if copied.validate().is_ok else null


## 复制记录的外壳并共享未修改的领域快照。
## 调用方必须在写入前替换其要变更的数组、字典或领域对象；共享对象视为只读。
## 该路径用于自动存档的按领域合并，避免每次移动都深拷贝成就和全部装备状态。
func shallow_copy() -> PlayerStateRecord:
	var copied := PlayerStateRecord.new()
	copied.account_id = account_id
	copied.account_name = account_name
	copied.account_status = account_status
	copied.character_id = character_id
	copied.display_name = display_name
	copied.revision = revision
	copied.inventory_revision = inventory_revision
	copied.vehicle_loadout_revision = vehicle_loadout_revision
	copied.inventory_capacity = inventory_capacity
	copied.inventory_stacks = inventory_stacks.duplicate()
	copied.warehouse = warehouse
	copied.production = production.duplicate_queue()
	copied.central = central
	copied.vehicle_presets = vehicle_presets
	copied.equipment_slots.clear()
	for slot: EquipmentSlotRecord in equipment_slots:
		copied.equipment_slots.append(slot.duplicate_record())
	copied.currency = currency
	copied.amethyst = amethyst
	copied.character_sex = character_sex
	copied.character_level = character_level
	copied.character_profession = character_profession
	copied.character_faction = character_faction
	copied.character_residence = character_residence
	copied.character_description = character_description
	copied.character_max_health = character_max_health
	copied.character_health = character_health
	copied.character_experience = character_experience
	copied.character_skills = character_skills
	copied.quest_states = quest_states
	copied.achievements = achievements
	copied.daily_activities = daily_activities
	copied.food_status = food_status
	copied.vehicle_id = vehicle_id
	copied.vehicle_definition_id = vehicle_definition_id
	copied.vehicle_max_health = vehicle_max_health
	copied.vehicle_health = vehicle_health
	copied.reserve_energy_capacity = reserve_energy_capacity
	copied.reserve_energy = reserve_energy
	copied.working_energy_capacity = working_energy_capacity
	copied.working_energy = working_energy
	copied.output_power = output_power
	copied.map_id = map_id
	copied.map_instance_id = map_instance_id
	copied.position = position
	copied.facing_direction = facing_direction
	copied.checkpoint_id = checkpoint_id
	copied.friend_ids = friend_ids.duplicate()
	copied.enemy_ids = enemy_ids.duplicate()
	copied.mailbox = mailbox.duplicate(true)
	return copied


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


static func _relation_ids(raw_value: Variant, field: String) -> DomainResult:
	if not raw_value is Array:
		return DomainResult.failure(&"persistence.invalid_player_state", "%s must be an array" % field)
	var ids: Array[String] = []
	for raw_id: Variant in raw_value:
		if not raw_id is String or String(raw_id).is_empty() or String(raw_id) in ids:
			return DomainResult.failure(&"persistence.invalid_player_state", "%s contains an invalid identity" % field)
		ids.append(String(raw_id))
	return DomainResult.ok(ids)


static func _mailbox(raw_value: Variant, owner_id: String = "") -> DomainResult:
	if not raw_value is Array:
		return DomainResult.failure(&"persistence.invalid_player_state", "mailbox must be an array")
	if raw_value.size() > 100:
		return DomainResult.failure(&"persistence.invalid_player_state", "mailbox contains too many messages")
	var messages: Array[Dictionary] = []
	var message_ids: Dictionary = {}
	for raw_message: Variant in raw_value:
		if not raw_message is Dictionary:
			return DomainResult.failure(&"persistence.invalid_player_state", "mailbox entry must be a dictionary")
		var message: Dictionary = raw_message
		var message_id := String(message.get("mail_id", ""))
		var sender_id := String(message.get("sender_entity_id", ""))
		var sender_name := String(message.get("sender_name", ""))
		var recipient_id := String(message.get("recipient_entity_id", ""))
		var section_value: Variant = message.get("section", "mail")
		var section := String(section_value)
		var subject := String(message.get("subject", ""))
		var body := String(message.get("body", ""))
		var sent_at_value: Variant = message.get("sent_at_msec", -1)
		var read_value: Variant = message.get("read", false)
		if message_id.is_empty() or message_ids.has(message_id) or sender_id.is_empty() \
			or sender_name.is_empty() or recipient_id.is_empty() or recipient_id != owner_id \
			or not (section_value is String) or section not in ["mail", "leaveword"] or subject.is_empty() \
			or subject.length() > 60 or body.is_empty() or body.length() > 1000 \
			or not (sent_at_value is int or sent_at_value is float) \
			or not is_finite(float(sent_at_value)) or float(sent_at_value) < 0.0 \
			or not (read_value is bool):
			return DomainResult.failure(&"persistence.invalid_player_state", "mailbox entry is invalid")
		message_ids[message_id] = true
		messages.append({
			"mail_id": message_id,
			"sender_entity_id": sender_id,
			"sender_name": sender_name,
			"recipient_entity_id": recipient_id,
			"section": section,
			"subject": subject,
			"body": body,
			"sent_at_msec": int(sent_at_value),
			"read": read_value,
		})
	return DomainResult.ok(messages)
