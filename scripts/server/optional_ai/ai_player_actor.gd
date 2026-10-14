class_name AiPlayerActor
extends RefCounted

var key := ""
var entity_id := ""
var peer_id := 0
var goal := ""
var sequence := 0
var action: AiPlayerAction
var action_map := ""
var action_deadline := 0
var action_performed := false
var next_step := 0
var next_decision := 0
var last_move_target := Vector2.INF
var failures := 0
var paused := false
var pending_request := 0
var memory := ""
var history: Array[Dictionary] = []


## 生成此角色独有的单调命令序号，不能由模型指定。
## 返回新的正整数序号。
func next_sequence() -> int:
	sequence += 1
	return sequence


## 记下实际执行结果，限制内存和持久化体积；不记录模型原文或私有快照。
## [param result] 权威入口或行动执行器的结果。[param timestamp] 当前单调时间。
func remember(result: DomainResult, timestamp: int) -> void:
	history.append({"kind": action.kind if action != null else "decision", "code": String(result.error_code),
		"ok": result.is_ok, "map_id": action_map, "time_msec": timestamp})
	if history.size() > 20: history.pop_front()
