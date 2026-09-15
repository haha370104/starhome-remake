class_name SkillLevelMessageFormatter
extends RefCounted

const DISPLAY_NAMES := {
	"energy_cannon": "能量炮",
	"repair": "维修",
	"driving": "驾驶",
	"mining": "采矿",
	"cooking": "烹饪",
	"tailoring": "裁缝",
	"refining": "提炼",
	"manufacturing": "制造",
	"processing": "加工",
	"rocket_launcher": "火箭炮",
	"missile": "导弹",
	"stealth": "隐身",
	"radar": "雷达",
	"airship": "航天",
}


## 按荣耀版 `OnSkillLevelUp` 的固定句式构造本地化系统提示。
## [param skill_id] 发生升级的技能业务标识。
## [param level] 权威服务器确认的新等级。
## 返回可直接进入 HUD 系统消息队列的中文提示。
static func format(skill_id: String, level: int) -> String:
	var display_name := String(DISPLAY_NAMES.get(skill_id, skill_id))
	return "你的%s操作技能提升到%d级！" % [display_name, level]
