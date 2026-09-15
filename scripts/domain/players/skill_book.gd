class_name SkillBook
extends RefCounted

const SkillStateScript := preload("res://scripts/domain/skills/skill_state.gd")
const SkillProgressionScript := preload("res://scripts/domain/skills/skill_progression.gd")

const ORDERED_SKILLS := [
	"energy_cannon", "repair", "driving", "mining", "cooking", "tailoring",
	"refining", "manufacturing", "processing", "rocket_launcher", "missile",
	"stealth", "radar",
]
const DISPLAY_NAMES := {
	"energy_cannon": "能量炮", "repair": "维修", "driving": "驾驶", "mining": "采矿",
	"cooking": "烹饪", "tailoring": "裁缝", "refining": "提炼", "manufacturing": "制造",
	"processing": "加工", "rocket_launcher": "火箭", "missile": "导弹",
	"stealth": "隐身", "radar": "雷达", "airship": "飞行器",
}

var _states: Dictionary = {}
var food_status: FoodStatus


## 初始化玩家的完整技能状态集合，并兼容旧存档中的纯整数等级。
## [param serialized_states] 技能标识到整数等级或技能状态字典的映射。
## 设计：SkillBook 是技能状态的一致性边界，调用方不能直接修改内部 SkillState。
func _init(serialized_states: Dictionary = {}) -> void:
	for raw_skill_id: Variant in serialized_states:
		var skill_id := String(raw_skill_id)
		if skill_id.is_empty():
			continue
		var raw_state: Variant = serialized_states[raw_skill_id]
		if raw_state is Dictionary:
			_states[skill_id] = SkillStateScript.new(
				StringName(skill_id),
				maxi(0, int(raw_state.get("level", 0))),
				maxi(0, int(raw_state.get("current_exp", 0))),
				maxf(0.0, float(raw_state.get("fractional_exp", 0.0))),
			)
		else:
			_states[skill_id] = SkillStateScript.new(
				StringName(skill_id), maxi(0, int(raw_state))
			)


## 查询技能基础等级。
## [param skill_id] 技能稳定标识。
## 返回不存在时为零的基础等级。
func base_level(skill_id: String) -> int:
	var state := _states.get(skill_id) as SkillState
	return state.level if state != null else 0


## 查询技能当前等级内的整数经验。
## [param skill_id] 技能稳定标识。
## 返回不存在时为零的当前经验。
func current_experience(skill_id: String) -> int:
	var state := _states.get(skill_id) as SkillState
	return state.current_exp if state != null else 0


## 计算旧客户端技能窗可见的当前经验百分比。
## [param skill_id] 技能稳定标识。
## [param progression_config] 技能升级门槛配置。
## 返回 0 到 100 的整数百分比；未满级最多显示 99%。
func displayed_progress_percent(skill_id: String, progression_config: Dictionary) -> int:
	var state := _state_for(skill_id)
	var maximum_level := int(progression_config.get("maximum_level", 700))
	if state.level >= maximum_level:
		return 100
	var threshold_result := SkillProgressionScript.get_need_points(
		StringName(skill_id), state.level, progression_config
	)
	if not threshold_result.is_ok or int(threshold_result.value) <= 0:
		return 0
	var ratio := (float(state.current_exp) + state.fractional_exp) \
		/ float(threshold_result.value)
	return mini(99, floori(clampf(ratio, 0.0, 1.0) * 100.0))


## 计算包含人物服装加成的最终技能等级。
## [param skill_id] 技能稳定标识。
## [param character_equipment] 当前人物穿着对象。
## 返回基础等级与装备加成之和。
func effective_level(skill_id: String, character_equipment: CharacterEquipment) -> int:
	var modifiers := character_equipment.skill_modifiers() if character_equipment != null else {}
	return base_level(skill_id) + int(modifiers.get(skill_id, 0))


## 向单项技能发放一次经验，并严格执行“一次最多升一级、溢出清零”。
## [param skill_id] 技能稳定标识。
## [param amount] 本次权威事件换算出的经验，可含小数。
## [param progression_config] 技能阈值与等级上限配置。
## 返回升级标记、当前经验、门槛及丢弃溢出；非法技能或数值返回领域错误。
func grant_experience(
	skill_id: String,
	amount: float,
	progression_config: Dictionary,
) -> DomainResult:
	if not progression_config.get("coefficient_bands", {}) is Dictionary \
			or not progression_config["coefficient_bands"].has(skill_id):
		return DomainResult.failure(&"unknown_skill", "Unknown skill: %s" % skill_id)
	var state := _state_for(skill_id)
	var result := SkillProgressionScript.apply_exp(state, amount * (food_status.experience_multiplier(skill_id) if food_status != null else 1.0), progression_config)
	if not result.is_ok and result.error_code == &"skill_maximum_level":
		return DomainResult.ok({
			"skill_id": skill_id,
			"upgraded": false,
			"maximum_level": true,
			"new_level": state.level,
			"current_exp": state.current_exp,
			"fractional_exp": state.fractional_exp,
			"discarded_exp": amount,
		})
	if not result.is_ok:
		return result
	var value: Dictionary = result.value
	value["skill_id"] = skill_id
	value["maximum_level"] = false
	return DomainResult.ok(value)


## 按服务器配置计算当前技能集合对应的综合等级。
## [param progression_config] 含基准等级、初始综合等级及技能权重的配置。
## 返回取整后的综合等级；未知或暂未确认权重的技能按零权重处理。
## 设计：只使用基础技能等级，装备临时加成不会永久抬高综合等级。
func comprehensive_level(progression_config: Dictionary) -> int:
	var comprehensive: Dictionary = progression_config.get("comprehensive_level", {})
	var base_value := int(comprehensive.get("base_level", 10))
	var baseline := int(comprehensive.get("skill_baseline", 10))
	var weights: Dictionary = comprehensive.get("weights", {})
	var weighted_sum := 0.0
	for raw_skill_id: Variant in weights:
		var skill_id := String(raw_skill_id)
		weighted_sum += float(maxi(0, base_level(skill_id) - baseline)) \
			* maxf(0.0, float(weights[raw_skill_id]))
	return maxi(base_value, base_value + floori(weighted_sum))


## 导出持久化需要的完整技能状态映射。
## 返回内部数据的防御性序列化副本。
func to_dictionary() -> Dictionary:
	var serialized: Dictionary = {}
	var skill_ids := _states.keys()
	skill_ids.sort()
	for skill_id: String in skill_ids:
		var state: SkillState = _states[skill_id]
		serialized[skill_id] = {
			"level": state.level,
			"current_exp": state.current_exp,
			"fractional_exp": state.fractional_exp,
		}
	return serialized


## 构建旧客户端技能窗口所需的稳定顺序视图。
## [param character_equipment] 用于计算装备加成的人物穿着对象。
## [param progression_config] 用于计算当前等级升级门槛的公开成长配置。
## 返回含等级、装备加成、当前经验、门槛和进度比例的技能视图数组。
func to_view_array(
	character_equipment: CharacterEquipment,
	progression_config: Dictionary = {},
) -> Array[Dictionary]:
	var modifiers := character_equipment.skill_modifiers() if character_equipment != null else {}
	var result: Array[Dictionary] = []
	var maximum_level := int(progression_config.get("maximum_level", 700))
	for skill_id: String in ORDERED_SKILLS:
		var state := _state_for(skill_id)
		var threshold := 0
		if not progression_config.is_empty() and state.level < maximum_level:
			var threshold_result := SkillProgressionScript.get_need_points(
				StringName(skill_id), state.level, progression_config
			)
			if threshold_result.is_ok:
				threshold = int(threshold_result.value)
		var progress_percent := displayed_progress_percent(skill_id, progression_config) \
			if not progression_config.is_empty() else 0
		result.append({
			"id": skill_id,
			"display_name": String(DISPLAY_NAMES[skill_id]),
			"base_level": state.level,
			"equipment_bonus": int(modifiers.get(skill_id, 0)),
			"experience": state.current_exp,
			"fractional_experience": state.fractional_exp,
			"next_level_experience": threshold,
			"progress_ratio": clampf(
				(float(state.current_exp) + state.fractional_exp) / float(threshold), 0.0, 1.0
			) if threshold > 0 else 1.0,
			"progress_percent": progress_percent,
			"maximum_level": state.level >= maximum_level,
		})
	return result


## 获取技能内部状态，不存在时创建零级状态。
## [param skill_id] 技能稳定标识。
## 返回仅供 SkillBook 内部修改的 SkillState。
func _state_for(skill_id: String) -> SkillState:
	var state := _states.get(skill_id) as SkillState
	if state == null:
		state = SkillStateScript.new(StringName(skill_id))
		_states[skill_id] = state
	return state
