class_name EquipmentConditionLoadout
extends RefCounted

var _items: Dictionary[String, Equipment] = {}
var needs_recalculation := false
var needs_durability_sync := false


## 确认飞行中的芯片效果仍由当前完好的同一能量炮支持。
## [param instance_id] 开火时原炮的稳定身份。
## 返回仍装备健康能量炮时为真，维修/采掘臂和副武器不接受。
func has_healthy_cannon(instance_id: String) -> bool:
	var item: Equipment = _items.get(instance_id)
	return item is VehicleWeapon and item.durability > 0 and item.equipment_location == 1 and item.combat_mode() == "energy_cannon"


## 持有权威聚合本次装配的独立实例，仅供模拟使用，不携带界面或仓储依赖。
## [param player] 由服务端存档映射恢复的聚合；测试无装配时可为空。
func _init(player: Player = null) -> void:
	if player == null: return
	for item: Equipment in player.vehicle.loadout.items():
		_items[item.instance_id] = item
	for item: Equipment in player.character_equipment.items():
		_items[item.instance_id] = item


## 为一个模拟实体复制条件，避免地图缓存、测试模板或另一实例共享可变余量。
## 返回具有相同规则的独立运行期装配。
func duplicate_loadout() -> EquipmentConditionLoadout:
	var result := EquipmentConditionLoadout.new()
	for item: Equipment in _items.values():
		var copied: Equipment = item.get_script().new(item._definition, item.to_view_dictionary())
		copied.maintenance_profile = item.maintenance_profile
		copied.processing_rules = item.processing_rules
		copied.extra_attribute_rules = item.extra_attribute_rules
		copied.strengthening_profile = item.strengthening_profile
		copied.strengthening_rules = item.strengthening_rules
		copied.quality_profile = item.quality_profile
		copied.forging_rules = item.forging_rules
		copied.forging_profile = item.forging_profile
		if copied is VehicleEquipment:
			copied.generator_profile = (item as VehicleEquipment).generator_profile
			copied.crystal_source_profile = (item as VehicleEquipment).crystal_source_profile
			copied.crystal_source_rules = (item as VehicleEquipment).crystal_source_rules
			copied.austin_profile = (item as VehicleEquipment).austin_profile
			copied.austin_rules = (item as VehicleEquipment).austin_rules
			copied.central_profile = (item as VehicleEquipment).central_profile
			copied.central_rules = (item as VehicleEquipment).central_rules
			copied.sama_profile = (item as VehicleEquipment).sama_profile
			copied.sama_rules = (item as VehicleEquipment).sama_rules
		if copied is Clothing: copied.improvement_rules = (item as Clothing).improvement_rules
		copied.refresh_processed_stats()
		result._items[copied.instance_id] = copied
	return result


## 记录全身符合事件类型的装备使用；类型资格由装备自身判断。
## [param event] 实际发生的使用类型。
## [param amount] 次数或移动秒数。
## [param instance_id] 指定武器实例；空值表示所有适用装备。
func record_use(event: String, amount: float = 1.0, instance_id: String = "") -> void:
	for item: Equipment in _items.values():
		if instance_id.is_empty() or item.instance_id == instance_id:
			_record_item_use(item, event, amount)


## 按实际移动时间累计战车本体磨损。
## [param seconds] 本 tick 的实际移动秒数。
func record_vehicle_movement(seconds: float) -> void:
	for item: Equipment in _items.values():
		if item is VehicleChassis:
			_record_item_use(item, "vehicle_movement", seconds)


## 统计当前完好且占据四个固定护甲位的装配。
## 返回参与本次伤害分摊的护甲数量。
func vehicle_armor_count() -> int:
	var count := 0
	for item: Equipment in _items.values():
		if item is VehicleEquipment and item.durability > 0 \
			and (item as VehicleEquipment).equipment_location in [5, 6, 7, 8]:
			count += 1
	return count


## 按最终扣血折算耐久，每件有效护甲分担总量的两成，护甲间按权重分配。
## [param damage] 最终扣除的战车生命。
## [param random_values] 每件护甲一个由独立权威随机流生成的非负权重。
func record_vehicle_damage(damage: int, random_values: Array[float]) -> void:
	if damage <= 0:
		return
	var chassis: VehicleChassis = null
	var armors: Array[Equipment] = []
	for item: Equipment in _items.values():
		if item is VehicleChassis and chassis == null:
			chassis = item as VehicleChassis
		elif item is VehicleEquipment and item.durability > 0 \
			and (item as VehicleEquipment).equipment_location in [5, 6, 7, 8]:
			armors.append(item)
	if chassis == null or chassis.durability <= 0:
		return
	var total_wear := 0.5 + float(damage) / 8.0
	var armor_ratio := float(armors.size()) * 0.2
	_record_item_use(chassis, "vehicle_damage", total_wear * (1.0 - armor_ratio))
	if armors.is_empty():
		return
	var weights: Array[float] = []
	var total_weight := 0.0
	for index in armors.size():
		var weight := maxf(0.0, random_values[index]) if index < random_values.size() and is_finite(random_values[index]) else 1.0
		weights.append(weight)
		total_weight += weight
	if total_weight <= 0.0:
		weights.fill(1.0)
		total_weight = float(weights.size())
	for index in armors.size():
		_record_item_use(armors[index], "vehicle_damage", total_wear * armor_ratio * weights[index] / total_weight)


## 战车被击毁时，按本体耐久上限追加固定比例损耗。
func record_vehicle_destroyed() -> void:
	for item: Equipment in _items.values():
		if not item is VehicleChassis:
			continue
		var chassis := item as VehicleChassis
		var durability_before := chassis.durability
		chassis.wear(20 + ceili(float(chassis.max_durability) * 0.025))
		if chassis.durability != durability_before:
			needs_durability_sync = true
			if chassis.durability == 0:
				needs_recalculation = true
		return


## 在权威状态及面板增量已接纳后清除同步标记。
func clear_durability_sync() -> void:
	needs_durability_sync = false


## 交给装备结算使用量，分别标记整数耐久变化和首次损坏。
## [param item] 本次装配中的真实实例。
## [param event] 已确认的使用事件。
## [param amount] 次数、秒数或分摊的磨损量。
func _record_item_use(item: Equipment, event: String, amount: float) -> void:
	var durability_before := item.durability
	if item.record_use(event, amount):
		needs_recalculation = true
	if item.durability != durability_before:
		needs_durability_sync = true


## 检查当前装配实例是否仍可开火，不允许损坏后的第二次射击。
## [param instance_id] 由权威武器定义提供的实例标识。
## 返回有效或损坏错误；无实例的旧测试模板保留原行为。
func validate_shot(instance_id: String) -> DomainResult:
	var item: Equipment = _items.get(instance_id)
	if item != null and item.durability <= 0:
		return DomainResult.failure(&"equipment.broken", "武器已损坏，请维护或速修")
	if item != null and item.ammunition_capacity() > 0 and item.magazine.remaining <= 0:
		return DomainResult.failure(&"ammunition.empty", "弹药不足，请到基地或生产区补弹")
	return DomainResult.ok()


## 在射击已被接受后同时结算一发弹药和磨损，拒绝的攻击不会调用。
## [param instance_id] 权威武器实例。
func accept_shot(instance_id: String) -> void:
	var item: Equipment = _items.get(instance_id)
	if item == null: return
	if item.ammunition_capacity() > 0: item.magazine.consume()
	record_use("shot", 1, instance_id)


## 投影某件已装配武器的即时弹量。
## [param instance_id] 武器实例。
## 返回剩余/容量；无弹仓装备返回空字典。
func ammunition_for(instance_id: String) -> Dictionary:
	var item: Equipment = _items.get(instance_id)
	return {"remaining": item.magazine.remaining, "capacity": item.ammunition_capacity()} if item != null and item.ammunition_capacity() > 0 else {}


## 按实例导出实时耐久及使用余量，供持久化边界按身份合并。
## 返回与装配顺序无关的独立字典。
func snapshot() -> Dictionary:
	var result := {}
	for item: Equipment in _items.values():
		result[item.instance_id] = {"definition_id": item.definition_id, "durability": item.durability,
			"max_durability": item.max_durability, "usage": item.usage.to_dictionary(), "magazine": item.magazine.to_dictionary()}
	return result


## 按稳定装配顺序获取模拟中的发生器实例，弹药仍由同一装备对象持有。
## 返回仅有有效规则且未损坏的发生器列表。
func generators() -> Array[VehicleEquipment]:
	var result: Array[VehicleEquipment] = []
	for item: Equipment in _items.values():
		if item is VehicleEquipment and item.generator_profile != null and item.durability > 0: result.append(item)
	result.sort_custom(func(a: VehicleEquipment, b: VehicleEquipment) -> bool: return a.equipment_location < b.equipment_location)
	return result


## 按固定槽位选取有效奥斯格兰部件，不包括其他特殊装备系列。
## 返回共享本次权威模拟状态的装备列表。
func austin_equipment() -> Array[VehicleEquipment]:
	var result: Array[VehicleEquipment] = []
	for item: Equipment in _items.values():
		if item is VehicleEquipment and item.austin_profile != null and item.durability > 0: result.append(item)
	result.sort_custom(func(a: VehicleEquipment, b: VehicleEquipment) -> bool: return a.equipment_location < b.equipment_location)
	return result


## 按固定槽位获取健康的撒玛装备，临时能力只能引用当前装配实例。
## 返回当前权威模拟的有效部件。
func sama_equipment() -> Array[VehicleEquipment]:
	var result: Array[VehicleEquipment] = []
	for item: Equipment in _items.values():
		if item is VehicleEquipment and item.sama_profile != null and item.durability > 0: result.append(item)
	result.sort_custom(func(a: VehicleEquipment, b: VehicleEquipment) -> bool: return a.equipment_location < b.equipment_location)
	return result
