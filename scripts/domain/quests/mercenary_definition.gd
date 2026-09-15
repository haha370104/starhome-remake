class_name MercenaryDefinition
extends RefCounted

var id: String
var title: String
var grade: int
var quality: int
var points: int
var kind: int
var quantity: int
var reward: int
var target_id := ""
var description: String
var locations: Array = []


## 将原版条件转换为领域任务定义；目标在目录边界解析为运行 ID。
## [param raw] 原版任务的规范化配置。
## [param rewards] 复刻八档紫晶奖励。
func _init(raw: Dictionary, rewards: Array) -> void:
	id = String(raw.id)
	title = String(raw.title)
	grade = int(raw.grade)
	quality = int(raw.quality)
	points = int(raw.points)
	kind = int(raw.condition[0])
	quantity = int(raw.condition[2])
	reward = int(rewards[grade - 1])
	description = String(raw.description)


## 输出任务定义投影，不暴露可修改的内部对象。
## 返回窗口需要的规则与已确认目标位置。
func snapshot() -> Dictionary:
	return {"id": id, "title": title, "grade": grade, "quality": quality, "kind": kind,
		"quantity": quantity, "reward": reward, "points": points, "target_id": target_id,
		"description": description, "locations": locations.duplicate(), "currency_donation": is_currency_donation()}


## 区分原版 money 条件与需要消耗背包物品的收集条件。
## 返回是否为星际币捐赠。
func is_currency_donation() -> bool:
	return kind == 2 and target_id == "money"


## 查询交付目标的当前可用数量，锁定物品仍不参与材料计数。
## [param inventory] 玩家聚合内部的权威背包及金币余额。
## 返回可用于本次交付的数量。
func delivery_progress(inventory: Inventory) -> int:
	return inventory.currency if is_currency_donation() else inventory.count_consumable_definition(target_id)


## 按任务定义消费交付目标，不接受客户端传入数量或币种。
## [param inventory] 玩家聚合内部的权威背包及金币余额。
## 返回扣款、扣物成功或任务未完成的原因。
func consume_delivery(inventory: Inventory) -> DomainResult:
	var consumed := inventory.spend_currency(quantity) if is_currency_donation() else inventory.consume_definition(target_id, quantity)
	if not consumed.is_ok:
		return DomainResult.failure(&"daily.incomplete", "星际币余额不足" if is_currency_donation() else "所需材料不足，或材料已锁定")
	return consumed
