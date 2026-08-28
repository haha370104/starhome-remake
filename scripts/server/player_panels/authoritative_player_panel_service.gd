class_name AuthoritativePlayerPanelService
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")
const InventoryLayoutScript := preload("res://scripts/domain/inventory/inventory_layout.gd")
const EquipmentSlotRegistryScript := preload("res://scripts/domain/equipment/equipment_slot_registry.gd")

const LOADOUT_PATH := "res://data/gameplay/stage3/starter_loadout_v1.json"
const ITEM_PRESENTATION := {
	"recruit_tank": {
		"icon": "res://assets/ui/windows/inventory/items/recruit_tank.png",
		"dialog_texture": "res://assets/ui/windows/vehicle/preview/chassis.png",
		"dialog_anchor": [170, 200],
		"dialog_origin": [-77, 8],
		"z_layer": 10,
	},
	"beginner_engine": {
		"icon": "res://assets/ui/windows/inventory/items/beginner_engine.png",
		"dialog_texture": "res://assets/ui/windows/vehicle/preview/engine.png",
		"dialog_anchor": [130, 385],
		"dialog_origin": [-33, -15],
		"z_layer": 30,
	},
	"recruit_energy_cannon": {
		"icon": "res://assets/ui/windows/inventory/items/recruit_energy_cannon.png",
		"dialog_texture": "res://assets/ui/windows/vehicle/preview/primary_weapon.png",
		"dialog_anchor": [170, 200],
		"dialog_origin": [-32, -16],
		"z_layer": 20,
	},
	"male_sleeveless_shirt": {
		"icon": "res://assets/ui/windows/inventory/items/male_sleeveless_shirt.png",
		"dialog_texture": "res://assets/ui/windows/character/equipment/male_sleeveless_shirt.png",
		"dialog_anchor": [91, 274],
		"dialog_origin": [-37, -181],
		"z_layer": 60,
		"character_slot": "upper_body",
		"required_sex": "male",
	},
}

var _definitions: Dictionary = {}


## 读取受控装备目录并建立服务端定义索引。
## 返回加载成功的服务实例或资源格式错误。
## 设计：资源路径仅用于快照表现字段，安装槽位和数值判断始终读取服务端目录。
func initialize() -> DomainResult:
	if not FileAccess.file_exists(LOADOUT_PATH):
		return DomainResult.failure(&"panels.catalog_missing", "starter equipment catalog is missing")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOADOUT_PATH))
	if not parsed is Dictionary or not parsed.get("definitions") is Array:
		return DomainResult.failure(&"panels.catalog_invalid", "starter equipment catalog is invalid")
	_definitions.clear()
	for raw_definition: Variant in parsed["definitions"]:
		if not raw_definition is Dictionary:
			return DomainResult.failure(&"panels.catalog_invalid", "equipment definition must be a dictionary")
		var definition_id := String(raw_definition.get("id", ""))
		if definition_id.is_empty() or _definitions.has(definition_id):
			return DomainResult.failure(&"panels.catalog_invalid", "equipment definition identity is invalid")
		_definitions[definition_id] = raw_definition.duplicate(true)
	_definitions["male_sleeveless_shirt"] = {
		"id": "male_sleeveless_shirt",
		"kind": "character_clothing",
		"display_name": "无袖衫（男）",
		"description": "男兵日常训练时的一种训练上衣。",
		"stats": {
			"purchase_value": 250,
			"sell_value": 100,
			"clothing_class": 35,
			"wear_damage_per_hit": 14,
			"max_durability": 64,
			"skill_modifiers": {},
		},
	}
	return DomainResult.ok(self)


## 根据已登记角色状态执行查询或变更命令。
## [param state] 权威存档聚合副本。
## [param command] 仅含操作意图、实例标识、目标与 revision 的命令。
## 返回 candidate 与完整 panel_bundle；查询命令的 candidate 与输入等价。
## 设计：本服务不接触 peer 身份或仓储，调用方负责会话绑定与原子提交。
func execute(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	if state == null or _definitions.is_empty():
		return DomainResult.failure(&"panels.service_unavailable", "player panel service is unavailable")
	var command_type := StringName(command.get("type", ""))
	var candidate := state.duplicate_record()
	var changed := false
	match command_type:
		&"query":
			pass
		&"move_inventory_item":
			var moved := _move_inventory_item(candidate, command)
			if not moved.is_ok:
				return moved
			changed = true
		&"arrange_inventory":
			var arranged := _arrange_inventory(candidate, command)
			if not arranged.is_ok:
				return arranged
			changed = true
		&"equip_vehicle_item":
			var equipped := _equip_vehicle_item(candidate, command)
			if not equipped.is_ok:
				return equipped
			changed = true
		&"equip_character_item":
			var character_equipped := _equip_character_item(candidate, command)
			if not character_equipped.is_ok:
				return character_equipped
			changed = true
		&"unequip_character_item":
			var character_unequipped := _unequip_character_item(candidate, command)
			if not character_unequipped.is_ok:
				return character_unequipped
			changed = true
		&"unequip_vehicle_item":
			var unequipped := _unequip_vehicle_item(candidate, command)
			if not unequipped.is_ok:
				return unequipped
			changed = true
		_:
			return DomainResult.failure(&"panels.unknown_command", "unknown player panel command")
	var validation := candidate.validate()
	if not validation.is_ok:
		return validation
	return DomainResult.ok({
		"candidate": candidate,
		"changed": changed,
		"panel_bundle": build_bundle(candidate),
	})


## 从同一聚合构建人物、背包和战车三份一致快照。
## [param state] 已通过校验的权威玩家聚合。
## 返回包含 transaction_revision 的三面板快照。
func build_bundle(state: PlayerStateRecord) -> Dictionary:
	return {
		"transaction_revision": state.revision,
		"character": _character_snapshot(state),
		"inventory": _inventory_snapshot(state),
		"vehicle": _vehicle_snapshot(state),
	}


## 校验 revision 后移动单个背包物品。
## [param state] 待修改聚合。
## [param command] 包含 instance_id、position_px 与 inventory_revision 的命令。
## 返回成功或校验错误。
func _move_inventory_item(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	var revision := _require_inventory_revision(state, command)
	if not revision.is_ok:
		return revision
	var position_value: Variant = command.get("position_px")
	if not position_value is Array or position_value.size() != 2:
		return DomainResult.failure(&"inventory.invalid_position", "inventory position must contain two coordinates")
	var moved := InventoryLayoutScript.move_item(
		_inventory_items(state),
		String(command.get("instance_id", "")),
		Vector2i(int(position_value[0]), int(position_value[1])),
	)
	if not moved.is_ok:
		return moved
	return _replace_inventory(state, moved.value)


## 校验 revision 后由服务器重排背包。
## [param state] 待修改聚合。
## [param command] 包含 inventory_revision 的命令。
## 返回成功或布局错误。
func _arrange_inventory(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	var revision := _require_inventory_revision(state, command)
	if not revision.is_ok:
		return revision
	var arranged := InventoryLayoutScript.arrange(_inventory_items(state))
	if not arranged.is_ok:
		return arranged
	return _replace_inventory(state, arranged.value)


## 将背包实例原子安装到战车 Location，并把被替换装备放回背包。
## [param state] 待修改聚合。
## [param command] 包含实例、Location、背包及装配 revision 的命令。
## 返回成功或槽位、空间、revision 错误。
func _equip_vehicle_item(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	var revision := _require_equipment_revisions(state, command)
	if not revision.is_ok:
		return revision
	var instance_id := String(command.get("instance_id", ""))
	var location := int(command.get("location", -1))
	var source_index := -1
	for index in state.inventory_stacks.size():
		if state.inventory_stacks[index].stack_id == instance_id:
			source_index = index
			break
	if source_index < 0:
		return DomainResult.failure(&"inventory.item_not_found", "inventory item does not exist")
	var source = state.inventory_stacks[source_index]
	if source.locked:
		return DomainResult.failure(&"inventory.item_locked", "locked inventory item cannot be equipped")
	if not EquipmentSlotRegistryScript.accepts(source.item_definition_id, location):
		return DomainResult.failure(&"equipment.location_rejected", "item cannot be installed in the requested location")
	var replaced_index := _equipment_index(state, location)
	if replaced_index >= 0:
		var replaced = state.equipment_slots[replaced_index]
		var inventory_items := _inventory_items(state)
		inventory_items.remove_at(source_index)
		var position := InventoryLayoutScript.first_available_position(inventory_items, Vector2i(45, 45))
		if position.x < 0:
			return DomainResult.failure(&"inventory.no_space", "inventory has no room for the replaced equipment")
		var stack_result := _stack_from_equipment(replaced, state.inventory_stacks.size(), position)
		if not stack_result.is_ok:
			return stack_result
		state.inventory_stacks.append(stack_result.value)
		state.equipment_slots.remove_at(replaced_index)
	var raw_slot := {
		"owner_kind": "vehicle",
		"slot_id": _slot_id(location),
		"slot_location": location,
		"equip_kind": _equip_kind(source.item_definition_id),
		"item_instance_id": source.stack_id,
		"item_definition_id": source.item_definition_id,
		"max_durability": maxi(1, source.max_durability),
		"durability": mini(source.durability, maxi(1, source.max_durability)),
		"upgrade_level": 0,
	}
	var rebuilt := PlayerStateRecordScript.from_dictionary(_state_with_equipment_change(
		state, source_index, raw_slot
	))
	if not rebuilt.is_ok:
		return rebuilt
	_copy_from(state, rebuilt.value)
	state.inventory_revision += 1
	state.vehicle_loadout_revision += 1
	return DomainResult.ok()


## 将指定战车槽位装备卸载回背包。
## [param state] 待修改聚合。
## [param command] 包含 Location 及双 revision 的命令。
## 返回成功或找不到装备、背包无空间等错误。
func _unequip_vehicle_item(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	var revision := _require_equipment_revisions(state, command)
	if not revision.is_ok:
		return revision
	var location := int(command.get("location", -1))
	var equipment_index := _equipment_index(state, location)
	if equipment_index < 0:
		return DomainResult.failure(&"equipment.slot_empty", "vehicle equipment slot is empty")
	var position := InventoryLayoutScript.first_available_position(
		_inventory_items(state), Vector2i(45, 45)
	)
	if position.x < 0 or state.inventory_stacks.size() >= state.inventory_capacity:
		return DomainResult.failure(&"inventory.no_space", "inventory has no room for the unloaded equipment")
	var stack_result := _stack_from_equipment(
		state.equipment_slots[equipment_index], state.inventory_stacks.size(), position
	)
	if not stack_result.is_ok:
		return stack_result
	state.inventory_stacks.append(stack_result.value)
	state.equipment_slots.remove_at(equipment_index)
	state.inventory_revision += 1
	state.vehicle_loadout_revision += 1
	return DomainResult.ok()


## 将服装从背包原子穿到人物槽位，并把旧服装放回背包。
## [param state] 待修改聚合。
## [param command] 包含实例、人物槽位、背包 revision 和聚合 revision 的命令。
## 返回成功或性别、槽位、空间与 revision 错误。
func _equip_character_item(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	var revision := _require_character_revisions(state, command)
	if not revision.is_ok:
		return revision
	var instance_id := String(command.get("instance_id", ""))
	var slot_id := String(command.get("character_slot", ""))
	var source_index := -1
	for index in state.inventory_stacks.size():
		if state.inventory_stacks[index].stack_id == instance_id:
			source_index = index
			break
	if source_index < 0:
		return DomainResult.failure(&"inventory.item_not_found", "character clothing item does not exist")
	var source = state.inventory_stacks[source_index]
	var presentation: Dictionary = ITEM_PRESENTATION.get(source.item_definition_id, {})
	if slot_id.is_empty() or String(presentation.get("character_slot", "")) != slot_id:
		return DomainResult.failure(&"equipment.location_rejected", "clothing does not match the requested character slot")
	if String(presentation.get("required_sex", state.character_sex)) != state.character_sex:
		return DomainResult.failure(&"equipment.sex_rejected", "clothing does not match the character sex")
	var replaced_index := _character_equipment_index(state, slot_id)
	if replaced_index >= 0:
		var inventory_items := _inventory_items(state)
		inventory_items.remove_at(source_index)
		var replacement_position := InventoryLayoutScript.first_available_position(
			inventory_items, Vector2i(45, 45)
		)
		if replacement_position.x < 0:
			return DomainResult.failure(&"inventory.no_space", "inventory has no room for replaced clothing")
		var replacement_result := _stack_from_equipment(
			state.equipment_slots[replaced_index], state.inventory_stacks.size(), replacement_position
		)
		if not replacement_result.is_ok:
			return replacement_result
		state.inventory_stacks.append(replacement_result.value)
		state.equipment_slots.remove_at(replaced_index)
	var raw_slot := {
		"owner_kind": "character",
		"slot_id": slot_id,
		"slot_location": 0,
		"equip_kind": 10,
		"item_instance_id": source.stack_id,
		"item_definition_id": source.item_definition_id,
		"max_durability": maxi(1, source.max_durability),
		"durability": mini(source.durability, maxi(1, source.max_durability)),
		"upgrade_level": 0,
	}
	var rebuilt := PlayerStateRecordScript.from_dictionary(_state_with_equipment_change(
		state, source_index, raw_slot
	))
	if not rebuilt.is_ok:
		return rebuilt
	_copy_from(state, rebuilt.value)
	state.inventory_revision += 1
	return DomainResult.ok()


## 将人物服装卸回背包。
## [param state] 待修改聚合。
## [param command] 包含人物槽位及双 revision 的命令。
## 返回成功或空槽、空间、revision 错误。
func _unequip_character_item(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	var revision := _require_character_revisions(state, command)
	if not revision.is_ok:
		return revision
	var slot_id := String(command.get("character_slot", ""))
	var equipment_index := _character_equipment_index(state, slot_id)
	if equipment_index < 0:
		return DomainResult.failure(&"equipment.slot_empty", "character equipment slot is empty")
	var position := InventoryLayoutScript.first_available_position(
		_inventory_items(state), Vector2i(45, 45)
	)
	if position.x < 0 or state.inventory_stacks.size() >= state.inventory_capacity:
		return DomainResult.failure(&"inventory.no_space", "inventory has no room for unloaded clothing")
	var stack_result := _stack_from_equipment(
		state.equipment_slots[equipment_index], state.inventory_stacks.size(), position
	)
	if not stack_result.is_ok:
		return stack_result
	state.inventory_stacks.append(stack_result.value)
	state.equipment_slots.remove_at(equipment_index)
	state.inventory_revision += 1
	return DomainResult.ok()


## 构建人物面板快照。
## [param state] 权威玩家聚合。
## 返回身份、成长、穿着和增益数据。
func _character_snapshot(state: PlayerStateRecord) -> Dictionary:
	var worn_items: Array[Dictionary] = []
	for equipment in state.equipment_slots:
		if equipment.owner_kind != "character":
			continue
		worn_items.append(_equipment_snapshot(equipment))
	return {
		"revision": state.revision,
		"character_id": state.character_id,
		"display_name": state.display_name,
		"sex": state.character_sex,
		"level": state.character_level,
		"profession": state.character_profession,
		"faction": state.character_faction,
		"residence": state.character_residence,
		"experience": state.character_experience,
		"health": state.character_health,
		"max_health": state.character_max_health,
		"description": state.character_description,
		"skills": _skill_snapshot(state.character_skills),
		"worn_items": worn_items,
		"buffs": [],
	}


## 构建像素背包快照。
## [param state] 权威玩家聚合。
## 返回 revision、容器尺寸、物品列表、数量和货币。
func _inventory_snapshot(state: PlayerStateRecord) -> Dictionary:
	return {
		"revision": state.inventory_revision,
		"capacity": state.inventory_capacity,
		"container_id": InventoryLayoutScript.MAIN_CONTAINER_ID,
		"container_size": [InventoryLayoutScript.MAIN_SIZE.x, InventoryLayoutScript.MAIN_SIZE.y],
		"snap_size": InventoryLayoutScript.SNAP_SIZE,
		"item_count": state.inventory_stacks.size(),
		"currency": state.currency,
		"items": _inventory_items(state),
	}


## 构建战车装配快照与面板统计值。
## [param state] 权威玩家聚合。
## 返回装配 revision、Location 装备、预览层及统一战斗统计。
func _vehicle_snapshot(state: PlayerStateRecord) -> Dictionary:
	var equipped: Array[Dictionary] = []
	var total_weight := 0
	var propulsion := 0
	var primary_attack := 0
	var defense := 0
	var armor_by_location := {5: 0, 6: 0, 7: 0, 8: 0}
	for equipment in state.equipment_slots:
		if equipment.owner_kind != "vehicle":
			continue
		var snapshot := _equipment_snapshot(equipment)
		equipped.append(snapshot)
		var definition: Dictionary = _definitions.get(equipment.item_definition_id, {})
		var stats: Dictionary = definition.get("stats", {})
		total_weight += int(stats.get("weight", 0))
		propulsion += int(stats.get("drive", 0))
		primary_attack += int(stats.get("base_attack", 0))
		defense += int(stats.get("armor", 0))
		if armor_by_location.has(equipment.slot_location):
			armor_by_location[equipment.slot_location] += int(stats.get("armor", 0))
	equipped.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["location"]) < int(right["location"])
	)
	return {
		"revision": state.vehicle_loadout_revision,
		"vehicle_id": state.vehicle_id,
		"vehicle_definition_id": state.vehicle_definition_id,
		"display_name": _display_name(state.vehicle_definition_id),
		"equipped": equipped,
		"stats": {
			"health": state.vehicle_health,
			"max_health": state.vehicle_max_health,
			"max_health_base": _definition_stat(state.vehicle_definition_id, "max_health"),
			"max_health_bonus": maxi(0, state.vehicle_max_health - _definition_stat(state.vehicle_definition_id, "max_health")),
			"defense": defense,
			"defense_base": defense,
			"defense_bonus": 0,
			"armor_front": int(armor_by_location[5]),
			"armor_rear": int(armor_by_location[6]),
			"armor_left": int(armor_by_location[7]),
			"armor_right": int(armor_by_location[8]),
			"speed": propulsion,
			"energy_cannon_attack": primary_attack,
			"energy_cannon_attack_base": primary_attack,
			"energy_cannon_attack_bonus": 0,
			"missile_attack": 0,
			"rocket_attack": 0,
			"propulsion": propulsion,
			"output_power": state.output_power,
			"weight": total_weight,
			"self_repair_base": 0,
			"self_repair_bonus": 0,
			"extra_repair": 0,
			"reserve_energy": state.reserve_energy,
			"reserve_energy_capacity": state.reserve_energy_capacity,
			"working_energy": state.working_energy,
			"working_energy_capacity": state.working_energy_capacity,
		},
	}


## 将持久化物品转换为客户端安全快照。
## [param state] 权威玩家聚合。
## 返回可直接交给共享布局校验器的物品数组。
func _inventory_items(state: PlayerStateRecord) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for stack in state.inventory_stacks:
		var definition: Dictionary = _definitions.get(stack.item_definition_id, {})
		var presentation: Dictionary = ITEM_PRESENTATION.get(stack.item_definition_id, {})
		items.append({
			"instance_id": stack.stack_id,
			"definition_id": stack.item_definition_id,
			"display_name": String(definition.get("display_name", stack.item_definition_id)),
			"description": String(definition.get("description", "")),
			"amount": stack.quantity,
			"container_id": stack.container_id,
			"position_px": [stack.position_px.x, stack.position_px.y],
			"footprint_px": [stack.footprint_px.x, stack.footprint_px.y],
			"locked": stack.locked,
			"bound": stack.bound,
			"durability": stack.durability,
			"max_durability": stack.max_durability,
			"icon": String(presentation.get("icon", "")),
			"equipment_location": EquipmentSlotRegistryScript.location_for_definition(stack.item_definition_id),
			"character_slot": String(presentation.get("character_slot", "")),
		})
	return items


## 将装备记录转换为带表现元数据的安全快照。
## [param equipment] 服务端装备记录。
## 返回不含源目录路径的装备字典。
func _equipment_snapshot(equipment) -> Dictionary:
	var presentation: Dictionary = ITEM_PRESENTATION.get(equipment.item_definition_id, {})
	var definition: Dictionary = _definitions.get(equipment.item_definition_id, {})
	return {
		"owner_kind": equipment.owner_kind,
		"slot_id": equipment.slot_id,
		"instance_id": equipment.item_instance_id,
		"definition_id": equipment.item_definition_id,
		"display_name": _display_name(equipment.item_definition_id),
		"description": String(definition.get("description", "")),
		"stats": (definition.get("stats", {}) as Dictionary).duplicate(true),
		"location": equipment.slot_location,
		"location_name": "上衣" if equipment.owner_kind == "character" \
			else EquipmentSlotRegistryScript.display_name(equipment.slot_location),
		"equip_kind": equipment.equip_kind,
		"durability": equipment.durability,
		"max_durability": equipment.max_durability,
		"dialog_texture": String(presentation.get("dialog_texture", "")),
		"icon": String(presentation.get("icon", "")),
		"dialog_anchor": presentation.get("dialog_anchor", [205, 245]),
		"dialog_origin": presentation.get("dialog_origin", [0, 0]),
		"z_layer": int(presentation.get("z_layer", equipment.slot_location)),
	}


## 将权威技能字典转换为旧客户端“查看技能”窗口所需的稳定顺序。
## [param skills] 技能标识到基础等级的映射。
## 返回包含中文名、基础等级、装备加成和经验占位的技能数组。
func _skill_snapshot(skills: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ordered_ids := [
		"energy_cannon", "repair", "driving", "mining", "cooking", "tailoring",
		"refining", "manufacturing", "rocket_launcher", "missile", "stealth", "radar",
	]
	var names := {
		"energy_cannon": "能量炮", "repair": "维修", "driving": "驾驶", "mining": "采矿",
		"cooking": "烹饪", "tailoring": "裁缝", "refining": "提炼", "manufacturing": "制造",
		"rocket_launcher": "火箭", "missile": "导弹", "stealth": "隐身", "radar": "雷达",
	}
	for skill_id: String in ordered_ids:
		result.append({
			"id": skill_id,
			"display_name": String(names[skill_id]),
			"base_level": int(skills.get(skill_id, 0)),
			"equipment_bonus": 0,
			"experience": 0,
		})
	return result


## 查询某件定义中的整型属性。
## [param definition_id] 目录定义标识。
## [param stat_id] stats 内的属性名。
## 返回不存在时为 0 的整型属性。
func _definition_stat(definition_id: String, stat_id: String) -> int:
	var definition: Dictionary = _definitions.get(definition_id, {})
	var stats: Dictionary = definition.get("stats", {})
	return int(stats.get(stat_id, 0))


## 用新物品字典数组重建持久化记录并推进背包 revision。
## [param state] 待修改聚合。
## [param items] 已通过布局校验的新物品数组。
## 返回重建结果。
func _replace_inventory(state: PlayerStateRecord, items: Array) -> DomainResult:
	var raw := state.to_dictionary()
	var existing: Dictionary = {}
	for stack in state.inventory_stacks:
		existing[stack.stack_id] = stack.to_dictionary()
	var raw_stacks: Array[Dictionary] = []
	for item: Dictionary in items:
		var item_id := String(item["instance_id"])
		if not existing.has(item_id):
			return DomainResult.failure(&"inventory.item_not_found", "inventory item disappeared during layout update")
		var raw_stack: Dictionary = existing[item_id]
		raw_stack["container_id"] = item["container_id"]
		raw_stack["position_px"] = item["position_px"]
		raw_stack["footprint_px"] = item["footprint_px"]
		raw_stacks.append(raw_stack)
	raw["inventory_stacks"] = raw_stacks
	raw["inventory_revision"] = state.inventory_revision + 1
	var rebuilt := PlayerStateRecordScript.from_dictionary(raw)
	if not rebuilt.is_ok:
		return rebuilt
	_copy_from(state, rebuilt.value)
	return DomainResult.ok()


## 校验背包乐观锁 revision。
## [param state] 当前权威聚合。
## [param command] 客户端命令。
## 返回成功或 revision 冲突。
func _require_inventory_revision(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	if int(command.get("inventory_revision", -1)) != state.inventory_revision:
		return DomainResult.failure(&"inventory.revision_conflict", "inventory revision changed")
	return DomainResult.ok()


## 同时校验背包与战车装配 revision。
## [param state] 当前权威聚合。
## [param command] 客户端装备命令。
## 返回成功或任一 revision 冲突。
func _require_equipment_revisions(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	var inventory_revision := _require_inventory_revision(state, command)
	if not inventory_revision.is_ok:
		return inventory_revision
	if int(command.get("loadout_revision", -1)) != state.vehicle_loadout_revision:
		return DomainResult.failure(&"equipment.revision_conflict", "vehicle loadout revision changed")
	return DomainResult.ok()


## 校验人物换装所需的背包与玩家聚合 revision。
## [param state] 当前权威聚合。
## [param command] 客户端人物换装命令。
## 返回成功或 revision 冲突。
func _require_character_revisions(state: PlayerStateRecord, command: Dictionary) -> DomainResult:
	var inventory_revision := _require_inventory_revision(state, command)
	if not inventory_revision.is_ok:
		return inventory_revision
	if int(command.get("state_revision", -1)) != state.revision:
		return DomainResult.failure(&"equipment.revision_conflict", "character state revision changed")
	return DomainResult.ok()


## 查找指定 Location 的装备数组索引。
## [param state] 玩家聚合。
## [param location] 目标 Location。
## 返回索引；不存在返回 -1。
func _equipment_index(state: PlayerStateRecord, location: int) -> int:
	for index in state.equipment_slots.size():
		var equipment = state.equipment_slots[index]
		if equipment.owner_kind == "vehicle" and equipment.slot_location == location:
			return index
	return -1


## 查找人物装备槽位索引。
## [param state] 玩家聚合。
## [param slot_id] 人物业务槽位名。
## 返回索引；不存在返回 -1。
func _character_equipment_index(state: PlayerStateRecord, slot_id: String) -> int:
	for index in state.equipment_slots.size():
		var equipment = state.equipment_slots[index]
		if equipment.owner_kind == "character" and equipment.slot_id == slot_id:
			return index
	return -1


## 将装备转换为可放回背包的持久化字典并解析成记录。
## [param equipment] 待卸载装备记录。
## [param slot_index] 兼容旧存档的顺序槽位。
## [param position] 新的像素位置。
## 返回 InventoryStackRecord 结果。
func _stack_from_equipment(equipment, slot_index: int, position: Vector2i) -> DomainResult:
	var raw := {
		"stack_id": equipment.item_instance_id,
		"item_definition_id": equipment.item_definition_id,
		"quantity": 1,
		"slot_index": slot_index,
		"container_id": "main",
		"position_px": [position.x, position.y],
		"footprint_px": [45, 45],
		"locked": false,
		"bound": false,
		"max_durability": equipment.max_durability,
		"durability": equipment.durability,
	}
	return preload("res://scripts/server/persistence/inventory_stack_record.gd").from_dictionary(raw)


## 构造换装后的完整原始聚合字典。
## [param state] 当前聚合。
## [param removed_inventory_index] 将被安装的背包索引。
## [param raw_slot] 新装备槽位字典。
## 返回可交给 PlayerStateRecord 重建的字典。
func _state_with_equipment_change(
	state: PlayerStateRecord,
	removed_inventory_index: int,
	raw_slot: Dictionary,
) -> Dictionary:
	var raw := state.to_dictionary()
	var raw_stacks: Array = raw["inventory_stacks"]
	raw_stacks.remove_at(removed_inventory_index)
	for index in raw_stacks.size():
		raw_stacks[index]["slot_index"] = index
	raw["inventory_stacks"] = raw_stacks
	var raw_equipment: Array = raw["equipment_slots"]
	raw_equipment.append(raw_slot)
	raw["equipment_slots"] = raw_equipment
	return raw


## 用序列化边界把重建聚合内容复制到原对象引用。
## [param target] 调用者持有的可变聚合。
## [param source] 已校验的新聚合。
func _copy_from(target: PlayerStateRecord, source: PlayerStateRecord) -> void:
	target.account_id = source.account_id
	target.account_name = source.account_name
	target.account_status = source.account_status
	target.character_id = source.character_id
	target.display_name = source.display_name
	target.revision = source.revision
	target.inventory_revision = source.inventory_revision
	target.vehicle_loadout_revision = source.vehicle_loadout_revision
	target.inventory_capacity = source.inventory_capacity
	target.inventory_stacks = source.inventory_stacks
	target.equipment_slots = source.equipment_slots
	target.currency = source.currency
	target.character_sex = source.character_sex
	target.character_level = source.character_level
	target.character_profession = source.character_profession
	target.character_faction = source.character_faction
	target.character_residence = source.character_residence
	target.character_description = source.character_description
	target.character_max_health = source.character_max_health
	target.character_health = source.character_health
	target.character_experience = source.character_experience
	target.character_skills = source.character_skills.duplicate(true)
	target.vehicle_id = source.vehicle_id
	target.vehicle_definition_id = source.vehicle_definition_id
	target.vehicle_max_health = source.vehicle_max_health
	target.vehicle_health = source.vehicle_health
	target.reserve_energy_capacity = source.reserve_energy_capacity
	target.reserve_energy = source.reserve_energy
	target.working_energy_capacity = source.working_energy_capacity
	target.working_energy = source.working_energy
	target.output_power = source.output_power
	target.map_id = source.map_id
	target.map_instance_id = source.map_instance_id
	target.position = source.position
	target.facing_direction = source.facing_direction
	target.checkpoint_id = source.checkpoint_id


## 查询定义的中文显示名。
## [param definition_id] 装备定义标识。
## 返回目录显示名或原标识。
func _display_name(definition_id: String) -> String:
	var definition: Dictionary = _definitions.get(definition_id, {})
	return String(definition.get("display_name", definition_id))


## 将 Location 转为持久化字符串槽位名。
## [param location] 稳定 Location 编号。
## 返回业务槽位字符串。
func _slot_id(location: int) -> String:
	return {
		0: "chassis", 1: "primary_weapon", 2: "defense", 3: "propulsion",
		5: "front_armor", 6: "rear_armor", 7: "left_armor", 8: "right_armor",
		13: "tactical", 14: "secondary_power", 16: "control", 17: "amplifier",
		18: "energy_core",
	}.get(location, "extension_%d" % location)


## 查询兼容旧客户端的装备类别编号。
## [param definition_id] 装备定义标识。
## 返回装备类别；未知返回 -1。
func _equip_kind(definition_id: String) -> int:
	return {"recruit_tank": 0, "recruit_energy_cannon": 1, "beginner_engine": 3}.get(
		definition_id, -1
	)
