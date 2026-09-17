class_name EquipmentMemoryDescription
extends RefCounted

const NAMES := {"max_health": "生命", "output_power": "输出功率", "range": "射程", "drive": "推进力", "base_attack": "攻击", "ammunition_capacity": "载弹量",
	"double_damage_chance": "双倍伤害概率", "armor": "防御", "movement_speed": "速度"}


## 把模块的类型化记忆转成玩家可读说明，不暴露内部字段名。
## [param memory] 空白或单一成长记忆。
## [param catalog] 用于原装备和晶石名称的受控目录。
## 返回来源、成长和晶石明细。
static func describe(memory: EquipmentMemory, catalog: ItemCatalog) -> String:
	if not memory.has_growth(): return "空白记忆模块"
	var lines := PackedStringArray(["来源：" + catalog.display_name(memory.source_definition_id)])
	match memory.module_type:
		1:
			for attribute: String in memory.processing.to_dictionary().increments:
				lines.append("%s加工 +%d" % [NAMES.get(attribute, attribute), memory.processing.bonus(attribute)])
		7:
			for kind: int in memory.forging.extensions:
				lines.append("%s扩展：+%d" % [catalog.forging_rules.channels[kind].label, memory.forging.extensions[kind]])
		3, 4:
			for id: String in memory.extra.to_dictionary().levels:
				var channel: ExtraAttributeRules.Channel = catalog.extra_attribute_rules.channels[id]
				lines.append("%s：%d颗" % [catalog.display_name(channel.material_id), memory.extra.level(id)])
		5: lines.append("独立强化：%d星" % memory.strengthening.level)
		6:
			lines.append("孔位 %d，已开 %d" % [memory.sockets.capacity(), memory.sockets.opened_count()])
			for index in memory.sockets.capacity():
				var slot := memory.sockets.slot_at(index)
				if not slot.crystal_id.is_empty(): lines.append("第%d孔：%s，裂纹 %d%s" % [index + 1, catalog.display_name(slot.crystal_id), slot.cracks, "，绑定" if slot.bound else ""])
	return "\n".join(lines)
