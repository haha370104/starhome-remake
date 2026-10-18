class_name AiPlayerAction
extends RefCounted

const KINDS := ["wait", "move", "travel", "hunt", "mine", "harvest", "pickup", "self_repair", "return_base", "panel"]
const ABILITIES := ["energy_cannon.primary", "missile.primary", "rocket_launcher.primary"]
const PANEL_FIELDS := {
	"query_weapon_merchant": ["merchant_id"],
	"buy_from_weapon_merchant": ["merchant_id", "definition_id"],
	"sell_to_weapon_merchant": ["merchant_id", "instance_id", "quantity"],
	"accept_weapon_merchant_task": ["merchant_id", "task_id"],
	"turn_in_weapon_merchant_task": ["merchant_id", "task_id"],
	"abandon_weapon_merchant_task": ["merchant_id", "task_id"],
	"query_daily_activities": [],
	"query_manufacturing": ["station_id"],
	"query_production": ["station_id"],
	"start_production": ["station_id", "recipe_id", "cycles", "speed"],
	"pause_production": [], "resume_production": [], "cancel_production": [],
	"use_inventory_item": ["instance_id"],
	"equip_vehicle_item": ["instance_id", "location"],
	"equip_character_item": ["instance_id", "character_slot"],
	"split_inventory_item": ["instance_id", "quantity"],
	"merge_inventory_item": ["instance_id"],
}

var kind := "wait"
var target_id := ""
var position := Vector2.ZERO
var ability_id := "energy_cannon.primary"
var panel_command: Dictionary = {}
var memory := ""


## 将模型输出转换为受限行动，模型不能指定角色、版本、奖励或任意服务器命令。
## [param raw] 外部函数调用参数。
## 返回类型化行动或拒绝结果。
static func parse(raw: Variant) -> DomainResult:
	if not raw is Dictionary: return _invalid()
	for key: Variant in raw:
		if key not in ["kind", "target_id", "x", "y", "ability_id", "panel_command_json", "memory"]: return _invalid()
	if not raw.get("kind") is String or raw.kind not in KINDS: return _invalid()
	var action := AiPlayerAction.new()
	action.kind = raw.kind
	for key: String in ["target_id", "ability_id", "memory"]:
		if raw.has(key):
			if not raw[key] is String or raw[key].length() > 256: return _invalid()
			action.set(key, raw[key])
	for axis: String in ["x", "y"]:
		var value: Variant = raw.get(axis, 0)
		if not (value is float or value is int) or not is_finite(float(value)) or absf(float(value)) > 100000: return _invalid()
	action.position = Vector2(float(raw.get("x", 0)), float(raw.get("y", 0)))
	if action.kind in ["travel", "hunt", "mine", "harvest", "pickup"] and action.target_id.is_empty(): return _invalid()
	if action.kind == "hunt" and action.ability_id not in ABILITIES: return _invalid()
	if action.kind == "panel":
		var encoded: Variant = raw.get("panel_command_json", "")
		if not encoded is String or encoded.length() > 2048: return _invalid()
		var command: Variant = JSON.parse_string(encoded)
		if not command is Dictionary or not command.get("type") is String or not PANEL_FIELDS.has(command.type): return _invalid()
		for key: Variant in command:
			if key != "type" and key not in PANEL_FIELDS[command.type]: return _invalid()
			var value: Variant = command[key]
			if value is String:
				if value.length() > 128: return _invalid()
			elif not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 10000: return _invalid()
		action.panel_command = command.duplicate(true)
	return DomainResult.ok(action)


## 描述严格的单次行动函数；没有未接入的社交工具，也不提供代码执行接口。
## 返回Responses API函数工具定义。
static func tool_definition() -> Dictionary:
	var properties := {"kind": {"type": "string", "enum": KINDS},
		"target_id": {"type": "string"}, "x": {"type": "number"}, "y": {"type": "number"},
		"ability_id": {"type": "string"}, "panel_command_json": {"type": "string"}, "memory": {"type": "string"}}
	return {"type": "function", "name": "choose_action", "strict": true,
		"description": "选择一次游戏行动。target_id只能来自当前观察；move使用x/y；hunt选择已有武器能力。panel使用允许的命令JSON。未用字段填空串或0；memory为不超过256字的下步计划。",
		"parameters": {"type": "object", "properties": properties, "required": properties.keys(), "additionalProperties": false}}


## 构造统一的边界错误，避免将原始模型输出注入系统日志。
## 返回无权限或格式错误结果。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"ai.invalid_action", "AI行动格式或权限不合法")
