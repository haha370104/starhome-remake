class_name EquipmentForgingDescription
extends RefCounted

const LABELS := {"max_health": "生命", "output_power": "输出", "drive": "推进", "base_attack": "攻击", "range": "射程", "ammunition_capacity": "载弹"}


## 整理每件装备可锻造方向和已获得的独立扩展。
## [param item] 已验证装备。
## [param rules] 锻造规则。
## 返回加工页内可直接展示的文本。
static func describe(item: Equipment, rules: EquipmentForgingRules) -> String:
	var lines := PackedStringArray()
	if item.forging_profile == null: return ""
	for kind: int in item.forging_profile.limits:
		var channel: EquipmentForgingRules.Channel = rules.channels[kind]
		lines.append("%s扩展：+%d / +%d" % [channel.label, item.forging.extensions.get(kind, 0), item.forging_profile.limits[kind]])
	return "\n".join(lines)


## 将普通加工事实转成清除前的可读摘要。
## [param state] 已验证的加工状态。
## 返回各项独立增量。
static func processing(state: Dictionary) -> String:
	var lines := PackedStringArray()
	for key: String in state.get("increments", {}):
		lines.append("%s+%d" % [LABELS.get(key, key), int(state.increments[key])])
	return "、".join(lines)
