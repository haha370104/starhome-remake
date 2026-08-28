class_name ServerSession
extends RefCounted

var session_id := ""
var peer_id := 0
var entity_id := ""
var map_instance_id := ""
var last_transition_sequence := -1
var reconnect_token := ""
var disconnected_at_msec := -1
var expires_at_msec := -1


## 判断 `has_active_peer` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func has_active_peer() -> bool:
	return peer_id > 0


## 执行 `snapshot` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func snapshot() -> Dictionary:
	return {
		"session_id": session_id,
		"peer_id": peer_id,
		"entity_id": entity_id,
		"map_instance_id": map_instance_id,
		"reconnect_token": reconnect_token,
		"connected": has_active_peer(),
		"expires_at_msec": expires_at_msec,
	}
