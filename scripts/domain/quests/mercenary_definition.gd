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
		"description": description, "locations": locations.duplicate()}
