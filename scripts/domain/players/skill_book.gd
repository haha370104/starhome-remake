class_name SkillBook
extends RefCounted

const ORDERED_SKILLS := [
	"energy_cannon", "repair", "driving", "mining", "cooking", "tailoring",
	"refining", "manufacturing", "rocket_launcher", "missile", "stealth", "radar",
]
const DISPLAY_NAMES := {
	"energy_cannon": "能量炮", "repair": "维修", "driving": "驾驶", "mining": "采矿",
	"cooking": "烹饪", "tailoring": "裁缝", "refining": "提炼", "manufacturing": "制造",
	"rocket_launcher": "火箭", "missile": "导弹", "stealth": "隐身", "radar": "雷达",
}

var _base_levels: Dictionary = {}


## 初始化玩家技能基础等级集合。
## [param base_levels] 技能标识到非负等级的映射。
func _init(base_levels: Dictionary = {}) -> void:
	for skill_id: Variant in base_levels:
		_base_levels[String(skill_id)] = maxi(0, int(base_levels[skill_id]))


## 查询技能基础等级。
## [param skill_id] 技能稳定标识。
## 返回不存在时为零的基础等级。
func base_level(skill_id: String) -> int:
	return int(_base_levels.get(skill_id, 0))


## 计算包含人物服装加成的最终技能等级。
## [param skill_id] 技能稳定标识。
## [param character_equipment] 当前人物穿着对象。
## 返回基础等级与装备加成之和。
func effective_level(skill_id: String, character_equipment: CharacterEquipment) -> int:
	var modifiers := character_equipment.skill_modifiers() if character_equipment != null else {}
	return base_level(skill_id) + int(modifiers.get(skill_id, 0))


## 导出持久化需要的基础等级映射。
## 返回内部数据的防御性副本。
func to_dictionary() -> Dictionary:
	return _base_levels.duplicate(true)


## 构建旧客户端技能窗口所需的稳定顺序视图。
## [param character_equipment] 用于计算装备加成的人物穿着对象。
## 返回技能视图数组。
func to_view_array(character_equipment: CharacterEquipment) -> Array[Dictionary]:
	var modifiers := character_equipment.skill_modifiers() if character_equipment != null else {}
	var result: Array[Dictionary] = []
	for skill_id: String in ORDERED_SKILLS:
		result.append({
			"id": skill_id,
			"display_name": String(DISPLAY_NAMES[skill_id]),
			"base_level": base_level(skill_id),
			"equipment_bonus": int(modifiers.get(skill_id, 0)),
			"experience": 0,
		})
	return result
