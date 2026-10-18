class_name PlayerPanelChange
extends RefCounted

var inventory_changed := false
var character_changed := false
var vehicle_changed := false
var skills_changed := false
var achievements_changed := false
var food_changed := false
var appearance_changed := false


## 对比已接纳的快照，生成展示订阅者关心的变化集合。
## [param previous] 上一份已接纳快照；首次同步为空。
## [param current] 本次已校验的权威快照。
## 返回不含玩法规则、可以合并的展示变更标记。
static func between(previous: Dictionary, current: Dictionary) -> PlayerPanelChange:
	var change := PlayerPanelChange.new()
	change.inventory_changed = previous.get("inventory") != current.get("inventory") or previous.get("wallet") != current.get("wallet")
	change.character_changed = previous.get("character") != current.get("character")
	change.vehicle_changed = previous.get("vehicle") != current.get("vehicle")
	change.skills_changed = previous.get("character", {}).get("skills") != current.get("character", {}).get("skills")
	change.achievements_changed = previous.get("achievements") != current.get("achievements")
	change.food_changed = previous.get("food_status") != current.get("food_status")
	change.appearance_changed = _appearance(previous) != _appearance(current)
	return change


## 合并同渲染帧接收的变化，不丢弃较早消息改变的部分。
## [param other] 已校验的下一次变化。
func merge(other: PlayerPanelChange) -> void:
	inventory_changed = inventory_changed or other.inventory_changed
	character_changed = character_changed or other.character_changed
	vehicle_changed = vehicle_changed or other.vehicle_changed
	skills_changed = skills_changed or other.skills_changed
	achievements_changed = achievements_changed or other.achievements_changed
	food_changed = food_changed or other.food_changed
	appearance_changed = appearance_changed or other.appearance_changed


## 提取决定人物和战车素材的身份及槽位；耐久、经验和金币不改变外观。
## [param bundle] 同事务的面板快照。
## 返回可稳定比较的轻量外观签名。
static func _appearance(bundle: Dictionary) -> Array:
	var signature: Array = [bundle.get("character", {}).get("sex", "")]
	for item: Dictionary in bundle.get("character", {}).get("worn_items", []) + bundle.get("vehicle", {}).get("equipped", []):
		signature.append([item.get("instance_id"), item.get("definition_id"), item.get("location"), item.get("slot_id")])
	return signature
