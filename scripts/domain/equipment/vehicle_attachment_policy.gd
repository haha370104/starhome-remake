class_name VehicleAttachmentPolicy
extends RefCounted

const FAMILY_SLOTS := {
	"old_joint": [16, 17], "new_joint": [32, 33], "generator": [14, 34],
}


## 在内容适配边界识别原版继承树，生成复刻装配契约；不修改原始归档。
## [param definition] 待规范化的装备定义。
static func adapt(definition: Dictionary) -> void:
	var ancestry := String(definition.get("source_audit", {}).get("inheritance", "")).split(" > ")
	var family := ""
	if "NewJointBase" in ancestry:
		family = "new_joint"
	elif "JointBase" in ancestry:
		family = "old_joint"
	elif int(definition.get("equipment_location", -1)) == 14:
		family = "generator"
	if family.is_empty():
		return
	definition["attachment_family"] = family
	definition["allowed_locations"] = FAMILY_SLOTS[family].duplicate()
	definition["equipment_location"] = FAMILY_SLOTS[family][0]
	definition["kind"] = "vehicle_equipment"
	if family == "old_joint" or family == "new_joint":
		var stats: Dictionary = definition.get("stats", {})
		var legacy: Dictionary = stats.get("legacy_properties", {})
		var values: Array[int] = []
		for part: String in String(legacy.get("m_szExLevelFunction", "")).trim_prefix("(").trim_suffix(")").split(","):
			if part.strip_edges().is_valid_int():
				values.append(int(part))
		stats["attachment_values"] = values
		var effect_kind := int(legacy.get("m_nExEquipKind", 0))
		var effects: Dictionary = {1: "energy_cannon_attack", 2: "missile_attack", 3: "rocket_attack", 4: "max_health"} \
			if family == "new_joint" else {1: "speed", 2: "max_health", 3: "radar", 4: "mining_time_ms", 5: "energy_cannon_attack"}
		stats["attachment_effect"] = effects.get(effect_kind, "")
		definition["stats"] = stats


## 查询某类装置允许使用的两个固定位置。
## [param family] 规范化的装置类别。
## 返回防御性副本；非装置返回空数组。
static func slots(family: String) -> Array:
	return FAMILY_SLOTS.get(family, []).duplicate()
