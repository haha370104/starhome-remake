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


## Reports whether the requested condition is satisfied.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func has_active_peer() -> bool:
	return peer_id > 0


## Serializes the current state into a transport-safe dictionary.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
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
