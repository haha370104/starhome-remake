class_name PlayerStateMapper
extends RefCounted

const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")

var _catalog: ItemCatalog


## 初始化存档 DTO 与纯领域 Player 之间的映射器。
## [param catalog] 已完成加载的物品类型目录。
func _init(catalog: ItemCatalog) -> void:
	_catalog = catalog


## 将权威持久化记录还原为充血 Player 聚合。
## [param record] 已通过持久化格式校验的记录。
## 返回完成类型组装的 Player 或目录、槽位、布局错误。
## 设计：持久化记录只负责序列化；所有业务行为从此边界进入 Player 及其子对象。
func to_domain(record: PlayerStateRecord) -> DomainResult:
	if record == null or _catalog == null:
		return DomainResult.failure(&"player.mapping_unavailable", "player mapper is unavailable")
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
		"skills": record.character_skills,
		"quest_states": record.quest_states,
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
	var inventory_items: Array[GameItem] = []
	for stack in record.inventory_stacks:
		var created := _catalog.create(stack.item_definition_id, {
			"instance_id": stack.stack_id,
			"quantity": stack.quantity,
			"container_id": stack.container_id,
			"position_px": [stack.position_px.x, stack.position_px.y],
			"footprint_px": [stack.footprint_px.x, stack.footprint_px.y],
			"locked": stack.locked,
			"bound": stack.bound,
			"max_durability": stack.max_durability,
			"durability": stack.durability,
		})
		if not created.is_ok:
			return created
		inventory_items.append(created.value)
	var inventory_result := player.inventory.restore_items(inventory_items)
	if not inventory_result.is_ok:
		return inventory_result
	for slot in record.equipment_slots:
		var created := _catalog.create(slot.item_definition_id, {
			"instance_id": slot.item_instance_id,
			"quantity": 1,
			"max_durability": slot.max_durability,
			"durability": slot.durability,
			"upgrade_level": slot.upgrade_level,
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
			if not created.value is VehicleEquipment \
				or (created.value as VehicleEquipment).equipment_location != slot.slot_location:
				return DomainResult.failure(&"player.invalid_vehicle_equipment", "persisted vehicle location does not match definition")
			var restored_vehicle := player.vehicle.loadout.restore(created.value)
			if not restored_vehicle.is_ok:
				return restored_vehicle
	return DomainResult.ok(player)


## 将领域 Player 完整映射回可持久化记录。
## [param player] 已完成领域操作的玩家聚合。
## 返回通过 PlayerStateRecord 校验的新记录。
func to_record(player: Player) -> DomainResult:
	if player == null:
		return DomainResult.failure(&"player.mapping_unavailable", "player is missing")
	var inventory_stacks: Array[Dictionary] = []
	var stack_index := 0
	for item: GameItem in player.inventory.items():
		var durability := 0
		var max_durability := 0
		if item is Equipment:
			durability = (item as Equipment).durability
			max_durability = (item as Equipment).max_durability
		inventory_stacks.append({
			"stack_id": item.instance_id,
			"item_definition_id": item.definition_id,
			"quantity": item.quantity,
			"slot_index": stack_index,
			"container_id": item.container_id,
			"position_px": [item.position_px.x, item.position_px.y],
			"footprint_px": [item.footprint_px.x, item.footprint_px.y],
			"locked": item.locked,
			"bound": item.bound,
			"max_durability": max_durability,
			"durability": durability,
		})
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
	return PlayerStateRecordScript.from_dictionary({
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
