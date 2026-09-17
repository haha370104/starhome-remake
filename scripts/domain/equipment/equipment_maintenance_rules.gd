class_name EquipmentMaintenanceRules
extends RefCounted

class Profile extends RefCounted:
	var regular_allowed: bool = false
	var quick_allowed: bool = false
	var no_wear: bool = true
	var wear_enabled: bool = false
	var family: String = ""
	var materials: Array[Dictionary] = []
	var currency: int = 0
	var skill_id: String = ""
	var required_skill_level: int = 0
	var experience: int = 0
	var maximum_loss_fraction: float = 0
	var native_maximum: int = 1
	var reason: String = ""
	var wear_thresholds: Dictionary = {}

class RepairTool extends RefCounted:
	var definition_id: String = ""
	var scope: String = ""
	var kind: String = ""
	var amount: int = 0

var _profiles: Dictionary[String, Profile] = {}
var _tools: Dictionary[String, RepairTool] = {}
var maintenance_maps: PackedStringArray = []


## 将独立维护规则转换为类型，不让界面或装备解析原版字段。
## [param data] 版本化配置。
## 返回目录或明确的配置错误。
static func from_dictionary(data: Dictionary) -> DomainResult:
	if data.get("schema_version") != 1:
		return DomainResult.failure(&"maintenance.rules_invalid", "维护规则版本无效")
	var rules := EquipmentMaintenanceRules.new()
	rules.maintenance_maps = PackedStringArray(data.get("maintenance_maps", []))
	for raw: Dictionary in data.get("equipment", []):
		var entry := Profile.new()
		var id := String(raw.get("definition_id", ""))
		entry.regular_allowed = bool(raw.get("regular_allowed", false))
		entry.quick_allowed = bool(raw.get("quick_allowed", false))
		entry.no_wear = bool(raw.get("no_wear", true))
		entry.wear_enabled = bool(raw.get("wear_enabled", false))
		entry.family = String(raw.get("family", ""))
		entry.currency = int(raw.get("currency", 0))
		entry.skill_id = String(raw.get("skill_id", ""))
		entry.required_skill_level = int(raw.get("required_skill_level", 0))
		entry.experience = int(raw.get("experience", 0))
		entry.maximum_loss_fraction = float(raw.get("maximum_loss_fraction", 0))
		entry.native_maximum = int(raw.get("native_maximum", 1))
		entry.reason = String(raw.get("reason", ""))
		if id.is_empty() or rules._profiles.has(id) or entry.family not in ["vehicle", "clothing"] \
			or entry.currency < 0 or entry.experience < 0 or entry.required_skill_level < 0 \
			or not is_finite(entry.maximum_loss_fraction) or entry.maximum_loss_fraction < 0 or entry.maximum_loss_fraction >= 1:
			return DomainResult.failure(&"maintenance.rules_invalid", "装备维护规则无效")
		for cost: Dictionary in raw.get("materials", []):
			if String(cost.get("definition_id", "")).is_empty() or int(cost.get("quantity", 0)) <= 0:
				return DomainResult.failure(&"maintenance.rules_invalid", "维护材料无效")
			entry.materials.append(cost.duplicate(true))
		rules._profiles[id] = entry
		entry.wear_thresholds = data.get("wear_thresholds", {}).duplicate(true)
		for event: String in entry.wear_thresholds:
			var threshold := float(entry.wear_thresholds[event])
			if event not in EquipmentUsage.EVENTS or not is_finite(threshold) or threshold <= 0:
				return DomainResult.failure(&"maintenance.rules_invalid", "装备磨损节奏无效")
	for raw: Dictionary in data.get("tools", []):
		var entry := RepairTool.new()
		entry.definition_id = String(raw.get("definition_id", ""))
		entry.scope = String(raw.get("scope", ""))
		entry.kind = String(raw.get("kind", ""))
		entry.amount = int(raw.get("amount", 0))
		if entry.definition_id.is_empty() or rules._tools.has(entry.definition_id) or entry.amount <= 0 \
			or entry.scope not in ["installed_one", "installed_all", "backpack_one"] or entry.kind not in ["points", "percent"]:
			return DomainResult.failure(&"maintenance.rules_invalid", "速修工具规则无效")
		rules._tools[entry.definition_id] = entry
	return DomainResult.ok(rules)


## 查询装备的维护资格。
## [param id] 定义标识。
## 返回规则或 null。
func profile(id: String) -> Profile:
	return _profiles.get(id)


## 查询速修工具的适用范围和恢复量。
## [param id] 定义标识。
## 返回工具规则或 null。
func repair_tool(id: String) -> RepairTool:
	return _tools.get(id)
