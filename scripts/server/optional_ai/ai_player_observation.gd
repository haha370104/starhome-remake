class_name AiPlayerObservation
extends RefCounted

class Target extends RefCounted:
	var id := ""
	var name := ""
	var position := Vector2.ZERO
	var health := 0
	var available := true

	## 仅投影可见目标的有限信息。
	## 返回可交给模型的JSON数据。
	func to_dictionary() -> Dictionary:
		return {"id": id, "name": name, "position": [position.x, position.y], "health": health, "available": available}

var map_id := ""
var map_name := ""
var position := Vector2.ZERO
var moving := false
var combat_active := false
var health := 0
var max_health := 0
var targets: Dictionary[String, Array] = {}
var own_state: Dictionary = {}


## 查询当前观察内的目标，拒绝让模型凭空指定远处或其他地图实体。
## [param kind] 目标类别。[param id] 观察内的稳定身份。
## 返回目标或空值。
func find(kind: String, id: String) -> Target:
	for target: Target in targets.get(kind, []):
		if target.id == id: return target
	return null


## 形成单个角色有权看到的观察；内部目标先转换为纯值。
## 返回有限JSON快照，不含会话令牌、账号凭据或其他玩家背包。
func to_dictionary() -> Dictionary:
	var visible := {}
	for kind: String in targets:
		var rows: Array[Dictionary] = []
		for target: Target in targets[kind]: rows.append(target.to_dictionary())
		visible[kind] = rows
	return {"map_id": map_id, "map_name": map_name, "position": [position.x, position.y],
		"moving": moving, "combat_active": combat_active, "health": health, "max_health": max_health,
		"targets": visible, "self": own_state.duplicate(true)}
