class_name EquipmentConditionCapture
extends RefCounted


## 将模拟中的最新损耗按实例身份写回候选记录，不改变库存版本或装备其他成长。
## [param state] 服务端隔离的候选存档。
## [param conditions] 权威装配输出的状态。
static func apply(state: PlayerStateRecord, conditions: Dictionary) -> void:
	for slot: EquipmentSlotRecord in state.equipment_slots:
		var current: Dictionary = conditions.get(slot.item_instance_id, {})
		if current.get("definition_id", "") != slot.item_definition_id: continue
		slot.durability = int(current.durability)
		slot.max_durability = int(current.max_durability)
		slot.usage = EquipmentUsage.restore(current.usage).value
		slot.magazine = WeaponMagazine.restore(current.magazine).value
