class_name PlayerStateMapper
extends RefCounted

const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")

var _catalog: ItemCatalog
var _reward_policy: DomainResult


## 初始化存档 DTO 与纯领域 Player 之间的映射器。
## [param catalog] 已完成加载的物品类型目录。
## [param rewards] 由服务端组装的可选切面；省略时加载统一只读配置。
func _init(catalog: ItemCatalog, rewards: RewardPipeline = null) -> void:
	_catalog = catalog
	_reward_policy = DomainResult.ok(rewards) if rewards != null else RewardPolicyLoader.load_default()


## 将权威持久化记录还原为充血 Player 聚合。
## [param record] 已通过持久化格式校验的记录。
## 返回完成类型组装的 Player 或目录、槽位、布局错误。
## 设计：持久化记录只负责序列化；所有业务行为从此边界进入 Player 及其子对象。
func to_domain(record: PlayerStateRecord) -> DomainResult:
	if record == null or _catalog == null:
		return DomainResult.failure(&"player.mapping_unavailable", "player mapper is unavailable")
	if not _reward_policy.is_ok:
		return _reward_policy
	var player := Player.new({
		"account_id": record.account_id,
		"account_name": record.account_name,
		"account_status": record.account_status,
		"character_id": record.character_id,
		"display_name": record.display_name,
		"sex": record.character_sex,
		"level": record.character_level,
		"profession": record.character_profession,
		"faction": record.character_faction,
		"residence": record.character_residence,
		"description": record.character_description,
		"max_health": record.character_max_health,
		"health": record.character_health,
		"experience": record.character_experience,
		"revision": record.revision,
		"map_id": record.map_id,
		"map_instance_id": record.map_instance_id,
		"checkpoint_id": record.checkpoint_id,
		"position": record.position,
		"facing_direction": record.facing_direction,
		"inventory_capacity": record.inventory_capacity,
		"inventory_revision": record.inventory_revision,
		"currency": record.currency,
		"amethyst": record.amethyst,
		"skills": record.character_skills,
		"quest_states": record.quest_states,
		"achievements": record.achievements,
		"daily_activities": record.daily_activities,
		"food_status": record.food_status,
		"vehicle": {
			"vehicle_id": record.vehicle_id,
			"definition_id": record.vehicle_definition_id,
			"loadout_revision": record.vehicle_loadout_revision,
			"max_health": record.vehicle_max_health,
			"health": record.vehicle_health,
			"reserve_energy_capacity": record.reserve_energy_capacity,
			"reserve_energy": record.reserve_energy,
			"working_energy_capacity": record.working_energy_capacity,
			"working_energy": record.working_energy,
			"output_power": record.output_power,
		},
	})
	player.reward_pipeline = _reward_policy.value
	var inventory_items: Array[GameItem] = []
	for stack in record.inventory_stacks:
		var created := _catalog.create(stack.item_definition_id, stack.item_state())
		if not created.is_ok:
			return created
		inventory_items.append(created.value)
	var inventory_result := player.inventory.restore_items(inventory_items)
	if not inventory_result.is_ok:
		return inventory_result
	var warehouse_result := record.warehouse.to_domain(_catalog)
	if not warehouse_result.is_ok: return warehouse_result
	player.warehouse = warehouse_result.value
	player.production = record.production.duplicate_queue()
	player.vehicle_presets = VehicleLoadoutPresets.restore(record.vehicle_presets.to_dictionary()).value
	for slot in record.equipment_slots:
		var created := _catalog.create(slot.item_definition_id, {
			"instance_id": slot.item_instance_id,
			"equipped_character_slot": slot.slot_id if slot.owner_kind == "character" else "",
			"quantity": 1,
			"max_durability": slot.max_durability,
			"durability": slot.durability,
			"upgrade_level": slot.upgrade_level,
			"enhancement": slot.enhancement.to_dictionary(),
			"clothing_improvement": slot.clothing_improvement.to_dictionary(),
			"vehicle_sockets": slot.vehicle_sockets.to_dictionary(),
			"crystal_source": slot.crystal_source.to_dictionary(),
			"austin_glens": slot.austin_glens.to_dictionary(),
			"sama": slot.sama.to_dictionary(),
			"processing": slot.processing.to_dictionary(),
			"extra_attributes": slot.extra_attributes.to_dictionary(),
			"strengthening": slot.strengthening.to_dictionary(),
			"equipment_quality": slot.equipment_quality.to_dictionary(),
			"forging": slot.forging.to_dictionary(),
			"usage": slot.usage.to_dictionary(),
			"magazine": slot.magazine.to_dictionary(),
			"locked": slot.locked,
			"bound": slot.bound,
			"equipment_location": slot.slot_location,
			"footprint_px": [45, 45],
		})
		if not created.is_ok:
			return created
		if slot.owner_kind == "character":
			if not created.value is Clothing \
				or (created.value as Clothing).character_slot != slot.slot_id:
				return DomainResult.failure(&"player.invalid_character_equipment", "persisted clothing slot does not match definition")
			var restored_clothing := player.character_equipment.restore(created.value)
			if not restored_clothing.is_ok:
				return restored_clothing
		else:
			if created.value is VehicleEquipment and created.value.attachment_family == "new_joint" and slot.slot_location in [16, 17]:
				created.value.equipment_location = 32 if slot.slot_location == 16 else 33
			elif not created.value is VehicleEquipment \
				or not (created.value as VehicleEquipment).accepts_location(slot.slot_location):
				return DomainResult.failure(&"player.invalid_vehicle_equipment", "persisted vehicle location does not match definition")
			var restored_vehicle := player.vehicle.loadout.restore(created.value)
			if not restored_vehicle.is_ok:
				return restored_vehicle
	player.refresh_clothing_bonuses()
	player.vehicle.reconcile_loadout_state(record.food_status.is_empty())
	return DomainResult.ok(player)


## 将领域 Player 完整映射回可持久化记录。
## [param player] 已完成领域操作的玩家聚合。
## 返回通过 PlayerStateRecord 校验的新记录。
func to_record(player: Player) -> DomainResult:
	if player == null:
		return DomainResult.failure(&"player.mapping_unavailable", "player is missing")
	var warehouse_result := PersonalWarehouseRecord.from_domain(player.warehouse)
	if not warehouse_result.is_ok: return warehouse_result
	var inventory_stacks: Array[Dictionary] = []
	var stack_index := 0
	for item: GameItem in player.inventory.items():
		var recorded := InventoryStackRecord.from_item(item, stack_index)
		if not recorded.is_ok: return recorded
		inventory_stacks.append(recorded.value.to_dictionary())
		stack_index += 1
	var equipment_slots: Array[Dictionary] = []
	for clothing: Clothing in player.character_equipment.items():
		equipment_slots.append(_equipment_record(clothing, "character", clothing.character_slot, 0, 10))
	for equipment: VehicleEquipment in player.vehicle.loadout.items():
		equipment_slots.append(_equipment_record(
			equipment,
			"vehicle",
			_slot_id(equipment.equipment_location),
			equipment.equipment_location,
			equipment.equip_kind,
		))
	var result := PlayerStateRecordScript.from_dictionary({
		"schema_version": PlayerStateRecordScript.CURRENT_SCHEMA_VERSION,
		"account_id": player.account_id,
		"account_name": player.account_name,
		"account_status": player.account_status,
		"character_id": player.entity_id,
		"display_name": player.display_name,
		"revision": player.revision,
		"inventory_revision": player.inventory.revision,
		"vehicle_loadout_revision": player.vehicle.loadout.revision,
		"inventory_capacity": player.inventory.capacity,
		"currency": player.inventory.currency,
		"amethyst": player.amethyst.balance(),
		"character_sex": player.sex,
		"character_level": player.level,
		"character_profession": player.profession,
		"character_faction": player.faction,
		"character_residence": player.residence,
		"character_description": player.description,
		"inventory_stacks": inventory_stacks,
		"equipment_slots": equipment_slots,
		"character_max_health": player.max_health,
		"character_health": player.health,
		"character_experience": player.experience,
		"character_skills": player.skills.to_dictionary(),
		"quest_states": player.quest_states.duplicate(true),
		"achievements": player.achievements.to_dictionary(),
		"daily_activities": player.daily_activities.to_dictionary(),
		"food_status": player.food_status.to_dictionary(),
		"production": player.production.to_dictionary(),
		"vehicle_presets": player.vehicle_presets.to_dictionary(),
		"vehicle_id": player.vehicle.vehicle_id,
		"vehicle_definition_id": player.vehicle.definition_id,
		"vehicle_max_health": player.vehicle.max_health,
		"vehicle_health": player.vehicle.health,
		"reserve_energy_capacity": player.vehicle.reserve_energy_capacity,
		"reserve_energy": player.vehicle.reserve_energy,
		"working_energy_capacity": player.vehicle.working_energy_capacity,
		"working_energy": player.vehicle.working_energy,
		"output_power": player.vehicle.output_power,
		"map_id": player.map_id,
		"map_instance_id": player.map_instance_id,
		"position": [player.position.x, player.position.y],
		"facing_direction": player.facing_direction,
		"checkpoint_id": player.checkpoint_id,
	})
	if not result.is_ok: return result
	result.value.warehouse = warehouse_result.value
	var checked: DomainResult = result.value.validate()
	return result if checked.is_ok else checked


## 将装备实例转换为持久化槽位记录。
## [param equipment] 待保存装备实例。
## [param owner_kind] character 或 vehicle。
## [param slot_id] 业务槽位标识。
## [param location] 稳定 Location 编号。
## [param equip_kind] 旧客户端装备类别编号。
## 返回 EquipmentSlotRecord 对应字典。
func _equipment_record(
	equipment: Equipment,
	owner_kind: String,
	slot_id: String,
	location: int,
	equip_kind: int,
) -> Dictionary:
	return {
		"owner_kind": owner_kind,
		"slot_id": slot_id,
		"item_instance_id": equipment.instance_id,
		"item_definition_id": equipment.definition_id,
		"max_durability": equipment.max_durability,
		"durability": equipment.durability,
		"upgrade_level": equipment.upgrade_level,
		"enhancement": (equipment as Clothing).enhancement.to_dictionary() if equipment is Clothing else {},
		"clothing_improvement": (equipment as Clothing).improvement.to_dictionary() if equipment is Clothing else {},
		"vehicle_sockets": (equipment as VehicleEquipment).sockets.to_dictionary() if equipment is VehicleEquipment else {},
		"crystal_source": (equipment as VehicleEquipment).crystal_source.to_dictionary() if equipment is VehicleEquipment else {},
		"austin_glens": (equipment as VehicleEquipment).austin_glens.to_dictionary() if equipment is VehicleEquipment else {},
		"sama": (equipment as VehicleEquipment).sama.to_dictionary() if equipment is VehicleEquipment else {},
		"processing": equipment.processing.to_dictionary(),
		"extra_attributes": equipment.extra_attributes.to_dictionary(),
		"strengthening": equipment.strengthening.to_dictionary(),
		"equipment_quality": equipment.quality.to_dictionary(),
		"forging": equipment.forging.to_dictionary(),
		"usage": equipment.usage.to_dictionary(),
		"magazine": equipment.magazine.to_dictionary(),
		"locked": equipment.locked,
		"bound": equipment.bound,
		"slot_location": location,
		"equip_kind": equip_kind,
	}


## 将稳定 Location 转为存档业务槽位名。
## [param location] 战车装备 Location。
## 返回兼容现有存档的槽位字符串。
func _slot_id(location: int) -> String:
	return {
		0: "chassis", 1: "primary_weapon", 2: "defense", 3: "propulsion",
		5: "front_armor", 6: "rear_armor", 7: "left_armor", 8: "right_armor",
		13: "tactical", 14: "secondary_power", 16: "control", 17: "amplifier",
		18: "energy_core",
	}.get(location, "extension_%d" % location)
