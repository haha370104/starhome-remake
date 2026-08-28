class_name CurrentPlayerState
extends RefCounted

signal changed(bundle: Dictionary)

var transaction_revision := -1
var character: Dictionary = {}
var inventory: Dictionary = {}
var vehicle: Dictionary = {}


## 用一组同事务版本的权威快照替换当前玩家客户端投影。
## [param bundle] 服务端下发的人物、背包、战车快照组。
## 返回快照是否完整并已应用。
## 设计：这是当前登录玩家在客户端的唯一只读聚合投影；它不计算属性，也不产生权威状态。
func apply_bundle(bundle: Dictionary) -> bool:
	if not bundle.get("character") is Dictionary \
			or not bundle.get("inventory") is Dictionary \
			or not bundle.get("vehicle") is Dictionary:
		return false
	transaction_revision = int(bundle.get("transaction_revision", -1))
	character = (bundle["character"] as Dictionary).duplicate(true)
	inventory = (bundle["inventory"] as Dictionary).duplicate(true)
	vehicle = (bundle["vehicle"] as Dictionary).duplicate(true)
	changed.emit(snapshot_bundle())
	return true


## 导出当前玩家投影的防御性副本。
## 返回人物、背包、战车与事务 revision 的完整快照组。
func snapshot_bundle() -> Dictionary:
	return {
		"transaction_revision": transaction_revision,
		"character": character.duplicate(true),
		"inventory": inventory.duplicate(true),
		"vehicle": vehicle.duplicate(true),
	}


## 查询当前玩家是否已有服务端快照。
## 返回至少成功应用过一组快照时为 true。
func is_ready() -> bool:
	return transaction_revision >= 0 and not character.is_empty() and not vehicle.is_empty()
