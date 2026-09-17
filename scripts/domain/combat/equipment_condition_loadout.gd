class_name EquipmentConditionLoadout
extends RefCounted

var _items: Dictionary[String, Equipment] = {}
var needs_recalculation := false


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
			if item.record_use(event, amount): needs_recalculation = true


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
