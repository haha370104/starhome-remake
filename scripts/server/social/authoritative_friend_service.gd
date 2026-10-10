class_name AuthoritativeFriendService
extends RefCounted

const DomainResultScript := preload("res://scripts/core/domain_result.gd")

const COMMANDS := [
	"query_friends",
	"friend_invite",
	"friend_invite_by_name",
	"friend_respond",
	"friend_remove",
	"enemy_add",
	"enemy_remove",
]

var _player_for_entity: Callable
var _map_for_entity: Callable
var _display_name_for_entity: Callable
var _is_active_for_entity: Callable
var _commit_relation: Callable
var _send_to_entity: Callable
var _find_active_entities_by_display_name: Callable
var _next_invite_number := 1
var _pending_invites: Dictionary = {}
var _configured := false


## 配置好友、仇人领域服务的查询、原子提交和可靠事件端口。
func configure(
	player_for_entity: Callable,
	map_for_entity: Callable,
	display_name_for_entity: Callable,
	is_active_for_entity: Callable,
	commit_relation: Callable,
	send_to_entity: Callable,
	find_active_entities_by_display_name: Callable = Callable(),
) -> DomainResult:
	for port: Callable in [
		player_for_entity,
		map_for_entity,
		display_name_for_entity,
		is_active_for_entity,
		commit_relation,
		send_to_entity,
	]:
		if not port.is_valid():
			return DomainResultScript.failure(&"friend.invalid_port", "all friend service ports are required")
	_player_for_entity = player_for_entity
	_map_for_entity = map_for_entity
	_display_name_for_entity = display_name_for_entity
	_is_active_for_entity = is_active_for_entity
	_commit_relation = commit_relation
	_send_to_entity = send_to_entity
	_find_active_entities_by_display_name = find_active_entities_by_display_name
	_configured = true
	return DomainResultScript.ok(self)


static func handles(command_type: String) -> bool:
	return command_type in COMMANDS


## 执行严格白名单内的好友、仇人命令。
func execute(actor_id: String, command: Dictionary) -> DomainResult:
	if not _configured:
		return _failure(&"friend.unavailable", "friend service is not configured")
	if actor_id.is_empty() or _player_for_entity.call(actor_id) == null:
		return _failure(&"friend.actor_missing", "actor has no authoritative player")
	var command_type := String(command.get("type", ""))
	match command_type:
		"query_friends":
			return DomainResultScript.ok(snapshot_for(actor_id)) if command.size() == 1 else _invalid_payload()
		"friend_invite":
			if not _exact_keys(command, ["type", "target_entity_id"]) or typeof(command.target_entity_id) != TYPE_STRING: return _invalid_payload()
			return _invite(actor_id, String(command.target_entity_id))
		"friend_invite_by_name":
			if not _exact_keys(command, ["type", "display_name"]) or typeof(command.display_name) != TYPE_STRING: return _invalid_payload()
			return _invite_by_name(actor_id, String(command.display_name).strip_edges())
		"friend_respond":
			if not _exact_keys(command, ["type", "invite_id", "accept"]) \
					or typeof(command.invite_id) != TYPE_STRING or typeof(command.accept) != TYPE_BOOL: return _invalid_payload()
			return _respond(actor_id, String(command.invite_id), bool(command.accept))
		"friend_remove":
			if not _exact_keys(command, ["type", "target_entity_id"]) or typeof(command.target_entity_id) != TYPE_STRING: return _invalid_payload()
			return _change_friend(actor_id, String(command.target_entity_id), false)
		"enemy_add", "enemy_remove":
			if not _exact_keys(command, ["type", "target_entity_id"]) or typeof(command.target_entity_id) != TYPE_STRING: return _invalid_payload()
			return _change_enemy(actor_id, String(command.target_entity_id), command_type == "enemy_add")
		_:
			return _failure(&"friend.unsupported_command", "unsupported friend command")


## 返回玩家当前的好友、仇人及待处理邀请投影。
func snapshot_for(entity_id: String) -> Dictionary:
	var player: Player = _player_for_entity.call(entity_id)
	if player == null:
		return {"friends": [], "enemies": [], "pending_invites": []}
	var friends: Array[Dictionary] = []
	for target_id: String in player.friend_ids:
		friends.append(_relation_snapshot(entity_id, target_id))
	var enemies: Array[Dictionary] = []
	for target_id: String in player.enemy_ids:
		enemies.append(_relation_snapshot(entity_id, target_id))
	var pending: Array[Dictionary] = []
	for invite: Dictionary in _pending_invites.values():
		if String(invite.target_entity_id) == entity_id:
			pending.append(_invite_snapshot(invite))
	return {"friends": friends, "enemies": enemies, "pending_invites": pending}


## 会话真正过期时丢弃相关邀请；已建立的关系由玩家存档继续保留。
func refresh_presence(entity_id: String) -> void:
	var player: Player = _player_for_entity.call(entity_id)
	if player == null: return
	var affected: Array[String] = [entity_id]
	for friend_id: String in player.friend_ids:
		if _is_active_for_entity.call(friend_id): affected.append(friend_id)
	_broadcast_state(affected)


func remove_expired_entity(entity_id: String) -> void:
	cancel_invites_for_entity(entity_id, "session_expired")


func cancel_invites_for_entity(entity_id: String, reason := "session_disconnected") -> void:
	for invite_id: String in _pending_invites.keys().duplicate():
		var invite: Dictionary = _pending_invites[invite_id]
		if String(invite.inviter_id) != entity_id and String(invite.target_entity_id) != entity_id:
			continue
		var other_id := String(invite.target_entity_id) if String(invite.inviter_id) == entity_id else String(invite.inviter_id)
		_pending_invites.erase(invite_id)
		_send_to_entity.call(other_id, {
			"type": "friend_invite_cancelled",
			"result": _wire_success({"invite_id": invite_id, "reason": reason}),
		})


## 按昵称精确定位唯一在线角色，再复用既有好友申请校验。
## [param actor_id] 申请方的权威角色标识。
## [param display_name] 玩家输入并去除首尾空白的昵称。
func _invite_by_name(actor_id: String, display_name: String) -> DomainResult:
	if display_name.is_empty() or display_name.length() > 64 \
			or "\n" in display_name or "\r" in display_name:
		return _failure(&"friend.invalid_name", "display name is invalid")
	if not _find_active_entities_by_display_name.is_valid():
		return _failure(&"friend.search_unavailable", "friend name search is unavailable")
	var candidates: Variant = _find_active_entities_by_display_name.call(display_name)
	if not candidates is Array or candidates.is_empty():
		return _failure(&"friend.target_missing", "target player is unavailable")
	if candidates.size() != 1:
		return _failure(&"friend.ambiguous_target", "more than one active player has this display name")
	return _invite(actor_id, String(candidates[0]))


func _invite(actor_id: String, target_id: String) -> DomainResult:
	if target_id.is_empty() or target_id == actor_id:
		return _failure(&"friend.invalid_target", "cannot add yourself as a friend")
	var actor: Player = _player_for_entity.call(actor_id)
	var target: Player = _player_for_entity.call(target_id)
	if target == null or not _is_active_for_entity.call(target_id):
		return _failure(&"friend.target_missing", "target player is unavailable")
	if target_id in actor.friend_ids or actor.enemy_ids.has(target_id) or target.enemy_ids.has(actor_id):
		return _failure(&"friend.relation_conflict", "the player already has a conflicting relation")
	for invite: Dictionary in _pending_invites.values():
		if String(invite.inviter_id) == actor_id and String(invite.target_entity_id) == target_id:
			return DomainResultScript.ok({"invite": _invite_snapshot(invite)})
	var invite := {
		"invite_id": "friend_invite_%d" % _next_invite_number,
		"inviter_id": actor_id,
		"target_entity_id": target_id,
	}
	_next_invite_number += 1
	_pending_invites[invite.invite_id] = invite
	_send_to_entity.call(target_id, {"type": "friend_invite", "result": _wire_success({"invite": _invite_snapshot(invite)})})
	return DomainResultScript.ok({"invite": _invite_snapshot(invite)})


func _respond(actor_id: String, invite_id: String, accept: bool) -> DomainResult:
	var invite: Dictionary = _pending_invites.get(invite_id, {})
	if invite.is_empty() or String(invite.target_entity_id) != actor_id:
		return _failure(&"friend.invite_missing", "friend invitation is unavailable")
	if not accept:
		_pending_invites.erase(invite_id)
		_send_to_entity.call(String(invite.inviter_id), {"type": "friend_invite_declined", "result": _wire_success({"invite_id": invite_id})})
		return DomainResultScript.ok({"declined": true})
	if not _is_active_for_entity.call(String(invite.inviter_id)):
		_pending_invites.erase(invite_id)
		return _failure(&"friend.inviter_missing", "inviter is no longer available")
	var committed: DomainResult = _commit_relation.call(String(invite.inviter_id), actor_id, "friend", true)
	if not committed.is_ok:
		return committed
	_pending_invites.erase(invite_id)
	for pending_id: String in _pending_invites.keys().duplicate():
		var pending: Dictionary = _pending_invites[pending_id]
		var same_direction := String(pending.inviter_id) == actor_id and String(pending.target_entity_id) == String(invite.inviter_id)
		var reverse_direction := String(pending.inviter_id) == String(invite.inviter_id) and String(pending.target_entity_id) == actor_id
		if same_direction or reverse_direction:
			_pending_invites.erase(pending_id)
	_broadcast_state([actor_id, String(invite.inviter_id)])
	return DomainResultScript.ok({"accepted": true, "friends": snapshot_for(actor_id)})


func _change_friend(actor_id: String, target_id: String, add: bool) -> DomainResult:
	var actor: Player = _player_for_entity.call(actor_id)
	if target_id.is_empty() or target_id == actor_id or not actor.friend_ids.has(target_id):
		return _failure(&"friend.not_found", "friend relation is unavailable")
	var committed: DomainResult = _commit_relation.call(actor_id, target_id, "friend", add)
	if not committed.is_ok: return committed
	_broadcast_state([actor_id, target_id])
	return DomainResultScript.ok({"friends": snapshot_for(actor_id)})


func _change_enemy(actor_id: String, target_id: String, add: bool) -> DomainResult:
	var actor: Player = _player_for_entity.call(actor_id)
	if target_id.is_empty() or target_id == actor_id:
		return _failure(&"friend.invalid_target", "invalid enemy target")
	if add and (_player_for_entity.call(target_id) == null or not _is_active_for_entity.call(target_id)):
		return _failure(&"friend.target_missing", "target player is unavailable")
	if add and actor.friend_ids.has(target_id):
		return _failure(&"friend.relation_conflict", "a friend cannot also be an enemy")
	if add == actor.enemy_ids.has(target_id):
		return _failure(&"friend.not_found", "enemy relation is unavailable")
	var committed: DomainResult = _commit_relation.call(actor_id, target_id, "enemy", add)
	if not committed.is_ok: return committed
	_send_to_entity.call(actor_id, {"type": "friend_state", "result": _wire_success(snapshot_for(actor_id))})
	return DomainResultScript.ok(snapshot_for(actor_id))


func _broadcast_state(entity_ids: Array) -> void:
	for entity_id: String in entity_ids:
		_send_to_entity.call(entity_id, {"type": "friend_state", "result": _wire_success(snapshot_for(entity_id))})


func _relation_snapshot(owner_id: String, entity_id: String) -> Dictionary:
	var owner_map_id := String(_map_for_entity.call(owner_id))
	var target_map_id := String(_map_for_entity.call(entity_id))
	return {
		"entity_id": entity_id,
		"display_name": String(_display_name_for_entity.call(entity_id)),
		"online": bool(_is_active_for_entity.call(entity_id)),
		"same_map": not owner_map_id.is_empty() and owner_map_id == target_map_id,
	}


func _invite_snapshot(invite: Dictionary) -> Dictionary:
	return {
		"invite_id": String(invite.invite_id),
		"inviter_id": String(invite.inviter_id),
		"inviter_name": String(_display_name_for_entity.call(String(invite.inviter_id))),
		"target_entity_id": String(invite.target_entity_id),
	}


func _exact_keys(command: Dictionary, keys: Array) -> bool:
	if command.size() != keys.size(): return false
	for key: String in keys:
		if not command.has(key): return false
	return true


func _wire_success(value: Dictionary) -> Dictionary:
	return {"ok": true, "code": "ok", "value": value}


func _invalid_payload() -> DomainResult:
	return _failure(&"friend.invalid_payload", "friend command contains an invalid field set")


func _failure(code: StringName, message: String) -> DomainResult:
	return DomainResultScript.failure(code, message)
