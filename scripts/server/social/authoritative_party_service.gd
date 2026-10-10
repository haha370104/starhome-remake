class_name AuthoritativePartyService
extends RefCounted

const DomainResultScript := preload("res://scripts/core/domain_result.gd")

const MAX_PARTY_SIZE := 5
const COMMANDS := [
	"query_party",
	"party_invite",
	"party_apply",
	"party_respond",
	"party_leave",
	"party_kick",
	"party_transfer_leader",
]

var _session_for_entity: Callable
var _map_for_entity: Callable
var _display_name_for_entity: Callable
var _is_active_for_entity: Callable
var _send_to_entity: Callable
var _next_party_number := 1
var _next_invite_number := 1
var _parties: Dictionary = {}
var _party_for_member: Dictionary = {}
var _pending_invites: Dictionary = {}
var _configured := false


## 配置组队领域服务的身份、地图和可靠事件端口。
## 组队状态只存在于服务端；断线宽限期内保留成员，过期会话由服务器显式移除。
func configure(
	session_for_entity: Callable,
	map_for_entity: Callable,
	display_name_for_entity: Callable,
	is_active_for_entity: Callable,
	send_to_entity: Callable,
) -> DomainResult:
	for port: Callable in [
		session_for_entity,
		map_for_entity,
		display_name_for_entity,
		is_active_for_entity,
		send_to_entity,
	]:
		if not port.is_valid():
			return DomainResultScript.failure(
				&"party.invalid_port", "all party service ports are required"
			)
	_session_for_entity = session_for_entity
	_map_for_entity = map_for_entity
	_display_name_for_entity = display_name_for_entity
	_is_active_for_entity = is_active_for_entity
	_send_to_entity = send_to_entity
	_configured = true
	return DomainResultScript.ok(self)


static func handles(command_type: String) -> bool:
	return command_type in COMMANDS


## 执行一个严格白名单的组队命令，并在成员变化后广播完整队伍投影。
func execute(actor_id: String, command: Dictionary) -> DomainResult:
	if not _configured:
		return _failure(&"party.unavailable", "party service is not configured")
	if actor_id.is_empty() or _session_for_entity.call(actor_id) == null:
		return _failure(&"party.actor_missing", "actor has no authoritative session")
	var command_type := String(command.get("type", ""))
	match command_type:
		"query_party":
			if command.size() != 1:
				return _invalid_payload()
			return DomainResultScript.ok({"party": snapshot_for(actor_id)})
		"party_invite":
			if not _exact_keys(command, ["type", "target_entity_id"]) or typeof(command.target_entity_id) != TYPE_STRING:
				return _invalid_payload()
			return _invite(actor_id, String(command.target_entity_id))
		"party_apply":
			if not _exact_keys(command, ["type", "target_entity_id"]) or typeof(command.target_entity_id) != TYPE_STRING:
				return _invalid_payload()
			return _apply(actor_id, String(command.target_entity_id))
		"party_respond":
			if not _exact_keys(command, ["type", "invite_id", "accept"]) \
					or typeof(command.invite_id) != TYPE_STRING or typeof(command.accept) != TYPE_BOOL:
				return _invalid_payload()
			return _respond(actor_id, String(command.invite_id), bool(command.accept))
		"party_leave":
			if command.size() != 1:
				return _invalid_payload()
			return _leave(actor_id)
		"party_kick":
			if not _exact_keys(command, ["type", "target_entity_id"]) or typeof(command.target_entity_id) != TYPE_STRING:
				return _invalid_payload()
			return _kick(actor_id, String(command.target_entity_id))
		"party_transfer_leader":
			if not _exact_keys(command, ["type", "target_entity_id"]) or typeof(command.target_entity_id) != TYPE_STRING:
				return _invalid_payload()
			return _transfer_leader(actor_id, String(command.target_entity_id))
		_:
			return _failure(&"party.unsupported_command", "unsupported party command")


## 返回角色当前所属队伍的只读传输副本；没有队伍时返回空成员列表。
func snapshot_for(entity_id: String) -> Dictionary:
	var party_id := String(_party_for_member.get(entity_id, ""))
	if party_id.is_empty() or not _parties.has(party_id):
		return {"party_id": "", "leader_id": "", "members": [], "pending_invites": _pending_invites_for(entity_id)}
	var party: Dictionary = _parties[party_id]
	var members: Array[Dictionary] = []
	for member_id: String in party.member_ids:
		members.append(_member_snapshot(member_id))
	return {
		"party_id": party_id,
		"leader_id": String(party.leader_id),
		"members": members,
		"pending_invites": _pending_invites_for(entity_id),
	}


## 返回当前队伍中可接收队伍聊天的在线成员。
func refresh_presence(entity_id: String) -> void:
	var party_id := String(_party_for_member.get(entity_id, ""))
	if not party_id.is_empty():
		_broadcast_party(party_id)


func active_members_for(entity_id: String) -> Array[String]:
	var party_id := String(_party_for_member.get(entity_id, ""))
	if party_id.is_empty() or not _parties.has(party_id):
		return []
	var members: Array[String] = []
	for member_id: String in _parties[party_id].member_ids:
		if _is_active_for_entity.call(member_id):
			members.append(member_id)
	return members


## 返回怪物死亡瞬间可参与该掉落的队员；没有队伍时返回 null，保留自由拾取。
func loot_recipients_for(killer_id: String, map_instance_id: String) -> Variant:
	var party_id := String(_party_for_member.get(killer_id, ""))
	if party_id.is_empty() or not _parties.has(party_id):
		return null
	var recipients: Array[String] = []
	var party: Dictionary = _parties[party_id]
	for member_id: String in party.member_ids:
		if not _is_active_for_entity.call(member_id):
			continue
		if String(_map_for_entity.call(member_id)) != map_instance_id:
			continue
		recipients.append(member_id)
	return recipients


## 会话真正过期时移除角色；断线宽限期内保留队伍关系，允许重连后继续组队。
func remove_expired_entity(entity_id: String) -> void:
	_leave_internal(entity_id, true)
	for invite_id: String in _pending_invites.keys().duplicate():
		var invite: Dictionary = _pending_invites[invite_id]
		if String(invite.inviter_id) != entity_id and String(invite.target_entity_id) != entity_id:
			continue
		var other_id := String(invite.target_entity_id) if String(invite.inviter_id) == entity_id else String(invite.inviter_id)
		_pending_invites.erase(invite_id)
		_send_to_entity.call(other_id, {
			"type": "party_invite_cancelled",
			"result": _wire_success({
				"invite_id": invite_id,
				"party_id": String(invite.party_id),
				"reason": "session_expired",
			}),
		})


func cancel_invites_for_entity(entity_id: String, reason := "map_changed") -> void:
	for invite_id: String in _pending_invites.keys().duplicate():
		var invite: Dictionary = _pending_invites[invite_id]
		if String(invite.inviter_id) != entity_id and String(invite.target_entity_id) != entity_id:
			continue
		var other_id := String(invite.target_entity_id) if String(invite.inviter_id) == entity_id else String(invite.inviter_id)
		_pending_invites.erase(invite_id)
		_send_to_entity.call(other_id, {
			"type": "party_invite_cancelled",
			"result": _wire_success({"invite_id": invite_id, "party_id": String(invite.party_id), "reason": reason}),
		})


func _invite(actor_id: String, target_id: String) -> DomainResult:
	if target_id.is_empty() or target_id == actor_id:
		return _failure(&"party.invalid_target", "party invite target is invalid")
	if _session_for_entity.call(target_id) == null or not _is_active_for_entity.call(target_id):
		return _failure(&"party.target_unavailable", "party invite target is offline")
	if String(_map_for_entity.call(actor_id)) != String(_map_for_entity.call(target_id)):
		return _failure(&"party.different_map", "party members must be in the same map")
	if not String(_party_for_member.get(target_id, "")).is_empty():
		return _failure(&"party.target_in_party", "target already belongs to a party")
	var party_id := String(_party_for_member.get(actor_id, ""))
	if party_id.is_empty():
		party_id = _create_party(actor_id)
	var party: Dictionary = _parties[party_id]
	if party.member_ids.size() >= MAX_PARTY_SIZE:
		return _failure(&"party.full", "party is full")
	for invite: Dictionary in _pending_invites.values():
		if invite.target_entity_id == target_id and invite.party_id == party_id:
			return _failure(&"party.invite_pending", "party invite is already pending")
	var invite_id := "party_invite_%d" % _next_invite_number
	_next_invite_number += 1
	var invite := {
		"invite_id": invite_id,
		"party_id": party_id,
		"inviter_id": actor_id,
		"target_entity_id": target_id,
		"created_at_msec": Time.get_ticks_msec(),
	}
	_pending_invites[invite_id] = invite
	_send_to_entity.call(target_id, {
		"type": "party_invite",
		"result": _wire_success({"invite": _invite_snapshot(invite), "party": _party_snapshot(party_id)}),
	})
	_broadcast_party(party_id)
	return DomainResultScript.ok({"party": snapshot_for(actor_id), "invite": _invite_snapshot(invite)})


func _apply(actor_id: String, target_id: String) -> DomainResult:
	if target_id.is_empty() or target_id == actor_id:
		return _failure(&"party.invalid_target", "party application target is invalid")
	if not _is_active_for_entity.call(actor_id) or not _is_active_for_entity.call(target_id):
		return _failure(&"party.target_unavailable", "party application target is offline")
	if not String(_party_for_member.get(actor_id, "")).is_empty():
		return _failure(&"party.already_in_party", "actor already belongs to a party")
	var party_id := String(_party_for_member.get(target_id, ""))
	var party: Dictionary = _parties.get(party_id, {})
	if party.is_empty():
		return _failure(&"party.target_not_in_party", "target does not belong to a party")
	if party.member_ids.size() >= MAX_PARTY_SIZE:
		return _failure(&"party.full", "party is full")
	if String(_map_for_entity.call(actor_id)) != String(_map_for_entity.call(party.leader_id)):
		return _failure(&"party.different_map", "party members must be in the same map")
	var leader_id := String(party.leader_id)
	if not _is_active_for_entity.call(leader_id):
		return _failure(&"party.target_unavailable", "party leader is offline")
	for invite: Dictionary in _pending_invites.values():
		if String(invite.get("kind", "invite")) == "join_request" \
				and String(invite.party_id) == party_id and String(invite.inviter_id) == actor_id:
			return DomainResultScript.ok({"invite": _invite_snapshot(invite)})
	var invite := {
		"invite_id": "party_invite_%d" % _next_invite_number,
		"party_id": party_id,
		"kind": "join_request",
		"inviter_id": actor_id,
		"target_entity_id": leader_id,
		"created_at_msec": Time.get_ticks_msec(),
	}
	_next_invite_number += 1
	_pending_invites[invite.invite_id] = invite
	_send_to_entity.call(leader_id, {
		"type": "party_join_request",
		"result": _wire_success({"invite": _invite_snapshot(invite), "party": snapshot_for(leader_id)}),
	})
	return DomainResultScript.ok({"invite": _invite_snapshot(invite)})


func _pending_invites_for(entity_id: String) -> Array[Dictionary]:
	var invites: Array[Dictionary] = []
	for invite: Dictionary in _pending_invites.values():
		if String(invite.target_entity_id) == entity_id:
			invites.append(_invite_snapshot(invite))
	return invites


func _respond(actor_id: String, invite_id: String, accept: bool) -> DomainResult:
	var invite: Dictionary = _pending_invites.get(invite_id)
	if invite.is_empty() or String(invite.target_entity_id) != actor_id:
		return _failure(&"party.invite_missing", "party invite is no longer available")
	var is_join_request := String(invite.get("kind", "invite")) == "join_request"
	if not accept:
		_pending_invites.erase(invite_id)
		_send_to_entity.call(invite.inviter_id, {
			"type": "party_invite_declined",
			"result": _wire_success({"invite_id": invite_id, "target_entity_id": actor_id}),
		})
		return DomainResultScript.ok({"party": snapshot_for(actor_id), "accepted": false})
	var party: Dictionary = _parties.get(String(invite.party_id), {})
	if party.is_empty() or party.member_ids.size() >= MAX_PARTY_SIZE:
		return _failure(&"party.unavailable", "party is no longer available")
	if is_join_request and String(party.leader_id) != actor_id:
		return _failure(&"party.not_leader", "only the party leader may accept applications")
	var joining_id := String(invite.inviter_id) if is_join_request else actor_id
	if not _is_active_for_entity.call(joining_id):
		return _failure(&"party.target_unavailable", "applicant is no longer online")
	if not String(_party_for_member.get(joining_id, "")).is_empty():
		return _failure(&"party.already_in_party", "applicant already belongs to a party")
	if String(_map_for_entity.call(joining_id)) != String(_map_for_entity.call(party.leader_id)):
		return _failure(&"party.different_map", "party members must be in the same map")
	_pending_invites.erase(invite_id)
	party.member_ids.append(joining_id)
	_party_for_member[joining_id] = String(invite.party_id)
	_cancel_join_requests_from(joining_id)
	_broadcast_party(String(invite.party_id))
	return DomainResultScript.ok({"party": snapshot_for(actor_id), "accepted": true, "member_entity_id": joining_id})


func _leave(actor_id: String) -> DomainResult:
	var party_id := String(_party_for_member.get(actor_id, ""))
	if party_id.is_empty():
		return _failure(&"party.not_in_party", "actor does not belong to a party")
	_leave_internal(actor_id, false)
	if _parties.has(party_id):
		_broadcast_party(party_id)
	return DomainResultScript.ok({"party": snapshot_for(actor_id)})


func _kick(actor_id: String, target_id: String) -> DomainResult:
	var party_id := String(_party_for_member.get(actor_id, ""))
	var party: Dictionary = _parties.get(party_id, {})
	if party.is_empty() or String(party.leader_id) != actor_id:
		return _failure(&"party.not_leader", "only the party leader may remove members")
	if target_id.is_empty() or target_id == actor_id or String(_party_for_member.get(target_id, "")) != party_id:
		return _failure(&"party.invalid_target", "target is not a party member")
	_leave_internal(target_id, false)
	_send_to_entity.call(target_id, {"type": "party_removed", "result": _wire_success({"party_id": party_id})})
	if _parties.has(party_id):
		_broadcast_party(party_id)
	return DomainResultScript.ok({"party": snapshot_for(actor_id), "removed_entity_id": target_id})


func _transfer_leader(actor_id: String, target_id: String) -> DomainResult:
	var party_id := String(_party_for_member.get(actor_id, ""))
	var party: Dictionary = _parties.get(party_id, {})
	if party.is_empty() or String(party.leader_id) != actor_id:
		return _failure(&"party.not_leader", "only the party leader may transfer leadership")
	if target_id.is_empty() or String(_party_for_member.get(target_id, "")) != party_id:
		return _failure(&"party.invalid_target", "target is not a party member")
	_cancel_join_requests_for_leader(actor_id)
	party.leader_id = target_id
	_broadcast_party(party_id)
	return DomainResultScript.ok({"party": snapshot_for(actor_id)})


func _create_party(leader_id: String) -> String:
	var party_id := "party_%d" % _next_party_number
	_next_party_number += 1
	_parties[party_id] = {
		"party_id": party_id,
		"leader_id": leader_id,
		"member_ids": [leader_id],
		"created_at_msec": Time.get_ticks_msec(),
	}
	_party_for_member[leader_id] = party_id
	_cancel_join_requests_from(leader_id)
	return party_id


func _cancel_invites_from(entity_id: String) -> void:
	for invite_id: String in _pending_invites.keys().duplicate():
		var invite: Dictionary = _pending_invites[invite_id]
		if String(invite.inviter_id) != entity_id:
			continue
		_pending_invites.erase(invite_id)
		_send_to_entity.call(String(invite.target_entity_id), {
			"type": "party_invite_cancelled",
			"result": _wire_success({"invite_id": invite_id, "party_id": String(invite.party_id)}),
		})


func _leave_internal(entity_id: String, expired: bool) -> void:
	var party_id := String(_party_for_member.get(entity_id, ""))
	if party_id.is_empty() or not _parties.has(party_id):
		_party_for_member.erase(entity_id)
		return
	var party: Dictionary = _parties[party_id]
	_cancel_invites_from(entity_id)
	party.member_ids.erase(entity_id)
	_party_for_member.erase(entity_id)
	if party.member_ids.is_empty():
		_parties.erase(party_id)
		for invite_id: String in _pending_invites.keys().duplicate():
			var invite: Dictionary = _pending_invites[invite_id]
			if String(invite.party_id) == party_id:
				_pending_invites.erase(invite_id)
				var recipient_id := String(invite.target_entity_id)
				if String(invite.get("kind", "invite")) == "join_request":
					recipient_id = String(invite.inviter_id)
				_send_to_entity.call(recipient_id, {
					"type": "party_invite_cancelled",
					"result": _wire_success({"invite_id": invite_id, "party_id": party_id}),
				})
		return
	if String(party.leader_id) == entity_id:
		_cancel_join_requests_for_leader(entity_id)
		party.leader_id = String(party.member_ids[0])
	if expired:
		_broadcast_party(party_id)


func _broadcast_party(party_id: String) -> void:
	if not _parties.has(party_id):
		return
	var party: Dictionary = _parties[party_id]
	for member_id: String in party.member_ids:
		_send_to_entity.call(member_id, {
			"type": "party_state",
			"result": _wire_success({"party": snapshot_for(member_id)}),
		})


func _party_snapshot(party_id: String) -> Dictionary:
	var party: Dictionary = _parties.get(party_id, {})
	if party.is_empty():
		return {"party_id": "", "leader_id": "", "members": []}
	var members: Array[Dictionary] = []
	for member_id: String in party.member_ids:
		members.append(_member_snapshot(member_id))
	return {"party_id": party_id, "leader_id": String(party.leader_id), "members": members}


func _member_snapshot(entity_id: String) -> Dictionary:
	return {
		"entity_id": entity_id,
		"display_name": String(_display_name_for_entity.call(entity_id)),
		"connected": bool(_is_active_for_entity.call(entity_id)),
	}


func _invite_snapshot(invite: Dictionary) -> Dictionary:
	return {
		"invite_id": String(invite.invite_id),
		"party_id": String(invite.party_id),
		"request_type": String(invite.get("kind", "invite")),
		"inviter_id": String(invite.inviter_id),
		"inviter_name": String(_display_name_for_entity.call(String(invite.inviter_id))),
		"target_entity_id": String(invite.target_entity_id),
	}


func _exact_keys(command: Dictionary, keys: Array[String]) -> bool:
	if command.size() != keys.size():
		return false
	for key: String in keys:
		if not command.has(key):
			return false
	return true


func _wire_success(value: Dictionary) -> Dictionary:
	return {"ok": true, "code": "ok", "value": value}


func _invalid_payload() -> DomainResult:
	return _failure(&"party.invalid_payload", "party command contains an invalid field set")


func _failure(code: StringName, message: String) -> DomainResult:
	return DomainResultScript.failure(code, message)

func _cancel_join_requests_from(entity_id: String) -> void:
	var changed_party_ids: Array[String] = []
	for invite_id: String in _pending_invites.keys().duplicate():
		var invite: Dictionary = _pending_invites[invite_id]
		if String(invite.get("kind", "invite")) != "join_request" \
				or String(invite.get("inviter_id", "")) != entity_id:
			continue
		var party_id := String(invite.get("party_id", ""))
		_pending_invites.erase(invite_id)
		if party_id not in changed_party_ids:
			changed_party_ids.append(party_id)
	for party_id: String in changed_party_ids:
		_broadcast_party(party_id)

func _cancel_join_requests_for_leader(entity_id: String) -> void:
	for invite_id: String in _pending_invites.keys().duplicate():
		var invite: Dictionary = _pending_invites[invite_id]
		if String(invite.get("kind", "invite")) != "join_request" \
				or String(invite.get("target_entity_id", "")) != entity_id:
			continue
		_pending_invites.erase(invite_id)
		_send_to_entity.call(String(invite.inviter_id), {
			"type": "party_invite_cancelled",
			"result": _wire_success({
				"invite_id": invite_id, "party_id": String(invite.party_id), "reason": "leader_changed",
			}),
		})
