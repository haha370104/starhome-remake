class_name ServerSession
extends RefCounted

var manufacturing_station := ""

var session_id := ""
var sync_id := ""
var peer_id := 0
var entity_id := ""
var is_llm := false
var map_instance_id := ""
var last_transition_sequence := -1
var last_recovery_sequence := -1
var reconnect_token := ""
var disconnected_at_msec := -1
var expires_at_msec := -1


## 判断 `has_active_peer` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func has_active_peer() -> bool:
	return peer_id > 0


## 判断角色是否仍由服务器作为在线玩家运行。
func is_online() -> bool:
	return has_active_peer() or is_llm


## 执行 `snapshot` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func snapshot() -> Dictionary:
	return {
		"session_id": session_id,
		"sync_id": sync_id,
		"peer_id": peer_id,
		"entity_id": entity_id,
		"map_instance_id": map_instance_id,
		"reconnect_token": "" if is_llm else reconnect_token,
		"connected": is_online(),
		"is_llm": is_llm,
		"expires_at_msec": expires_at_msec,
	}
