class_name AuthoritativeTradeService
extends RefCounted

const DomainResultScript := preload("res://scripts/core/domain_result.gd")

const COMMANDS := [
	"query_trade",
	"trade_invite",
	"trade_respond",
	"trade_add_item",
	"trade_remove_item",
	"trade_set_currency",
	"trade_ready",
	"trade_cancel",
]

var _session_for_entity: Callable
var _map_for_entity: Callable
var _display_name_for_entity: Callable
var _is_active_for_entity: Callable
var _validate_item: Callable
var _validate_currency: Callable
var _inventory_revision_for_entity: Callable
var _commit_trade: Callable
var _send_to_entity: Callable
var _next_trade_number := 1
var _next_invite_number := 1
var _pending_invites: Dictionary = {}
var _trades: Dictionary = {}
var _trade_for_entity: Dictionary = {}
var _configured := false


## 配置交易状态机；库存校验和最终原子提交由服务器注入，服务本身不持有玩家副本。
func configure(
	session_for_entity: Callable,
	map_for_entity: Callable,
	display_name_for_entity: Callable,
	is_active_for_entity: Callable,
	validate_item: Callable,
	validate_currency: Callable,
	inventory_revision_for_entity: Callable,
	commit_trade: Callable,
	send_to_entity: Callable,
) -> DomainResult:
	for port: Callable in [
		session_for_entity,
		map_for_entity,
		display_name_for_entity,
		is_active_for_entity,
		validate_item,
		validate_currency,
		inventory_revision_for_entity,
		commit_trade,
		send_to_entity,
	]:
		if not port.is_valid():
			return DomainResultScript.failure(&"trade.invalid_port", "all trade service ports are required")
	_session_for_entity = session_for_entity
	_map_for_entity = map_for_entity
	_display_name_for_entity = display_name_for_entity
	_is_active_for_entity = is_active_for_entity
	_validate_item = validate_item
	_validate_currency = validate_currency
	_inventory_revision_for_entity = inventory_revision_for_entity
	_commit_trade = commit_trade
	_send_to_entity = send_to_entity
	_configured = true
	return DomainResultScript.ok(self)


static func handles(command_type: String) -> bool:
	return command_type in COMMANDS


## 执行邀请、报价、锁定、取消和最终提交命令。
func execute(actor_id: String, command: Dictionary) -> DomainResult:
	if not _configured:
		return _failure(&"trade.unavailable", "trade service is not configured")
	if actor_id.is_empty() or _session_for_entity.call(actor_id) == null:
		return _failure(&"trade.actor_missing", "actor has no authoritative session")
	var command_type := String(command.get("type", ""))
	match command_type:
		"query_trade":
			return DomainResultScript.ok(_query_snapshot(actor_id)) if command.size() == 1 else _invalid_payload()
		"trade_invite":
			if not _exact_keys(command, ["type", "target_entity_id"]) or typeof(command.target_entity_id) != TYPE_STRING: return _invalid_payload()
			return _invite(actor_id, String(command.target_entity_id))
		"trade_respond":
			if not _exact_keys(command, ["type", "invite_id", "accept"]) \
					or typeof(command.invite_id) != TYPE_STRING or typeof(command.accept) != TYPE_BOOL: return _invalid_payload()
			return _respond(actor_id, String(command.invite_id), bool(command.accept))
		"trade_add_item":
			if not _exact_keys(command, ["type", "trade_id", "instance_id", "quantity"]) \
					or typeof(command.trade_id) != TYPE_STRING or typeof(command.instance_id) != TYPE_STRING \
					or typeof(command.quantity) != TYPE_INT: return _invalid_payload()
			return _add_item(actor_id, String(command.trade_id), String(command.instance_id), int(command.quantity))
		"trade_remove_item":
			if not _exact_keys(command, ["type", "trade_id", "instance_id"]) \
					or typeof(command.trade_id) != TYPE_STRING or typeof(command.instance_id) != TYPE_STRING: return _invalid_payload()
			return _remove_item(actor_id, String(command.trade_id), String(command.instance_id))
		"trade_set_currency":
			if not _exact_keys(command, ["type", "trade_id", "currency"]) \
					or typeof(command.trade_id) != TYPE_STRING or typeof(command.currency) != TYPE_INT: return _invalid_payload()
			return _set_currency(actor_id, String(command.trade_id), int(command.currency))
		"trade_ready":
			if not _exact_keys(command, ["type", "trade_id"]) or typeof(command.trade_id) != TYPE_STRING: return _invalid_payload()
			return _ready(actor_id, String(command.trade_id))
		"trade_cancel":
			if not _exact_keys(command, ["type", "trade_id"]) or typeof(command.trade_id) != TYPE_STRING: return _invalid_payload()
			return _cancel(actor_id, String(command.trade_id), "cancelled")
		_:
			return _failure(&"trade.unsupported_command", "unsupported trade command")


## 会话过期会直接取消未完成交易，不能把报价带入新的会话。
func remove_expired_entity(entity_id: String) -> void:
	var trade_id := String(_trade_for_entity.get(entity_id, ""))
	if not trade_id.is_empty():
		_cancel(entity_id, trade_id, "session_expired")
	for invite_id: String in _pending_invites.keys().duplicate():
		var invite: Dictionary = _pending_invites[invite_id]
		if String(invite.inviter_id) != entity_id and String(invite.target_entity_id) != entity_id:
			continue
		var other_id := String(invite.target_entity_id) if String(invite.inviter_id) == entity_id else String(invite.inviter_id)
		_pending_invites.erase(invite_id)
		_send_to_entity.call(other_id, {
			"type": "trade_invite_cancelled",
			"result": _wire_success({"invite_id": invite_id, "reason": "session_expired"}),
		})


func cancel_for_entity(entity_id: String, reason := "map_changed") -> void:
	var trade_id := String(_trade_for_entity.get(entity_id, ""))
	if not trade_id.is_empty():
		_cancel(entity_id, trade_id, reason)
	for invite_id: String in _pending_invites.keys().duplicate():
		var invite: Dictionary = _pending_invites[invite_id]
		if String(invite.inviter_id) != entity_id and String(invite.target_entity_id) != entity_id:
			continue
		var other_id := String(invite.target_entity_id) if String(invite.inviter_id) == entity_id else String(invite.inviter_id)
		_pending_invites.erase(invite_id)
		_send_to_entity.call(other_id, {
			"type": "trade_invite_cancelled",
			"result": _wire_success({"invite_id": invite_id, "reason": reason}),
		})


func _invite(actor_id: String, target_id: String) -> DomainResult:
	if target_id.is_empty() or target_id == actor_id:
		return _failure(&"trade.invalid_target", "trade invite target is invalid")
	if not _is_active_for_entity.call(target_id) or _session_for_entity.call(target_id) == null:
		return _failure(&"trade.target_unavailable", "trade invite target is offline")
	if not String(_trade_for_entity.get(actor_id, "")).is_empty() or not String(_trade_for_entity.get(target_id, "")).is_empty():
		return _failure(&"trade.already_active", "one party already has an active trade")
	if String(_map_for_entity.call(actor_id)) != String(_map_for_entity.call(target_id)):
		return _failure(&"trade.different_map", "trade target is not in the same map")
	for invite: Dictionary in _pending_invites.values():
		if String(invite.inviter_id) == actor_id and String(invite.target_entity_id) == target_id:
			return DomainResultScript.ok({"invite_id": String(invite.invite_id)})
	var invite_id := "trade_invite_%d" % _next_invite_number
	_next_invite_number += 1
	var invite := {
		"invite_id": invite_id,
		"inviter_id": actor_id,
		"target_entity_id": target_id,
	}
	_pending_invites[invite_id] = invite
	_send_to_entity.call(target_id, {"type": "trade_invite", "result": _wire_success({"invite": _invite_snapshot(invite)})})
	return DomainResultScript.ok({"invite_id": invite_id})


func _query_snapshot(actor_id: String) -> Dictionary:
	var trade_id := String(_trade_for_entity.get(actor_id, ""))
	var pending_invites: Array[Dictionary] = []
	for invite: Dictionary in _pending_invites.values():
		if String(invite.target_entity_id) == actor_id:
			pending_invites.append(_invite_snapshot(invite))
	return {"trade": _trade_snapshot(trade_id), "pending_invites": pending_invites}


func _respond(actor_id: String, invite_id: String, accept: bool) -> DomainResult:
	var invite: Dictionary = _pending_invites.get(invite_id, {})
	if invite.is_empty() or String(invite.target_entity_id) != actor_id:
		return _failure(&"trade.invite_missing", "trade invite is no longer available")
	if not accept:
		_pending_invites.erase(invite_id)
		_send_to_entity.call(invite.inviter_id, {"type": "trade_invite_declined", "result": _wire_success({"invite_id": invite_id})})
		return DomainResultScript.ok({"accepted": false})
	if _session_for_entity.call(invite.inviter_id) == null or not _is_active_for_entity.call(invite.inviter_id):
		return _failure(&"trade.target_unavailable", "trade inviter is no longer online")
	if String(_map_for_entity.call(invite.inviter_id)) != String(_map_for_entity.call(actor_id)):
		return _failure(&"trade.different_map", "trade participants must remain in the same map")
	if not String(_trade_for_entity.get(invite.inviter_id, "")).is_empty() or not String(_trade_for_entity.get(actor_id, "")).is_empty():
		return _failure(&"trade.already_active", "one party already has an active trade")
	_pending_invites.erase(invite_id)
	var trade_id := "trade_%d" % _next_trade_number
	_next_trade_number += 1
	var trade := {
		"trade_id": trade_id,
		"members": [String(invite.inviter_id), actor_id],
		"offers": {
			String(invite.inviter_id): _empty_offer(),
			actor_id: _empty_offer(),
		},
		"created_at_msec": Time.get_ticks_msec(),
	}
	_trades[trade_id] = trade
	_trade_for_entity[String(invite.inviter_id)] = trade_id
	_trade_for_entity[actor_id] = trade_id
	_cancel_invites_for_trade_members(trade.members)
	_broadcast_trade(trade_id)
	return DomainResultScript.ok({"trade": _trade_snapshot(trade_id)})


func _add_item(actor_id: String, trade_id: String, instance_id: String, quantity: int) -> DomainResult:
	var trade := _trade_for_actor(actor_id, trade_id)
	if trade.is_empty(): return _failure(&"trade.missing", "trade session is unavailable")
	if not _trade_in_same_map(trade): return _failure(&"trade.different_map", "trade participants must remain in the same map")
	if quantity <= 0 or instance_id.is_empty(): return _failure(&"trade.invalid_item", "trade item quantity is invalid")
	var offer: Dictionary = trade.offers[actor_id]
	if bool(offer.locked): return _failure(&"trade.locked", "unlock the trade before changing the offer")
	for item: Dictionary in offer.items:
		if String(item.instance_id) == instance_id:
			return _failure(&"trade.duplicate_item", "item is already in the trade offer")
	var checked: DomainResult = _validate_item.call(actor_id, instance_id, quantity)
	if not checked.is_ok: return checked
	var item_offer: Dictionary = checked.value.duplicate(true)
	item_offer["instance_id"] = instance_id
	item_offer["quantity"] = quantity
	offer.items.append(item_offer)
	_unlock_trade(trade)
	_broadcast_trade(trade_id)
	return DomainResultScript.ok({"trade": _trade_snapshot(trade_id)})


func _remove_item(actor_id: String, trade_id: String, instance_id: String) -> DomainResult:
	var trade := _trade_for_actor(actor_id, trade_id)
	if trade.is_empty(): return _failure(&"trade.missing", "trade session is unavailable")
	if not _trade_in_same_map(trade): return _failure(&"trade.different_map", "trade participants must remain in the same map")
	var offer: Dictionary = trade.offers[actor_id]
	if bool(offer.locked): return _failure(&"trade.locked", "unlock the trade before changing the offer")
	var removed := false
	for index: int in range(offer.items.size() - 1, -1, -1):
		if String(offer.items[index].instance_id) == instance_id:
			offer.items.remove_at(index)
			removed = true
			break
	if not removed: return _failure(&"trade.item_missing", "item is not in the trade offer")
	_unlock_trade(trade)
	_broadcast_trade(trade_id)
	return DomainResultScript.ok({"trade": _trade_snapshot(trade_id)})


func _set_currency(actor_id: String, trade_id: String, currency: int) -> DomainResult:
	var trade := _trade_for_actor(actor_id, trade_id)
	if trade.is_empty(): return _failure(&"trade.missing", "trade session is unavailable")
	if not _trade_in_same_map(trade): return _failure(&"trade.different_map", "trade participants must remain in the same map")
	var offer: Dictionary = trade.offers[actor_id]
	if bool(offer.locked): return _failure(&"trade.locked", "unlock the trade before changing the offer")
	var checked: DomainResult = _validate_currency.call(actor_id, currency)
	if not checked.is_ok: return checked
	offer.currency = currency
	offer.inventory_revision = int(checked.value.get("inventory_revision", 0))
	_unlock_trade(trade)
	_broadcast_trade(trade_id)
	return DomainResultScript.ok({"trade": _trade_snapshot(trade_id)})


func _ready(actor_id: String, trade_id: String) -> DomainResult:
	var trade := _trade_for_actor(actor_id, trade_id)
	if trade.is_empty(): return _failure(&"trade.missing", "trade session is unavailable")
	if not _trade_in_same_map(trade): return _failure(&"trade.different_map", "trade participants must remain in the same map")
	var offer: Dictionary = trade.offers[actor_id]
	var revision_result: DomainResult = _inventory_revision_for_entity.call(actor_id)
	if not revision_result.is_ok: return revision_result
	offer.inventory_revision = int(revision_result.value)
	offer.locked = true
	_broadcast_trade(trade_id)
	var other_id := _other_member(trade, actor_id)
	if not bool(trade.offers[other_id].locked):
		return DomainResultScript.ok({"trade": _trade_snapshot(trade_id), "committed": false})
	var committed: DomainResult = _commit_trade.call(trade.duplicate(true))
	if not committed.is_ok:
		_unlock_trade(trade)
		_broadcast_trade(trade_id)
		return committed
	_destroy_trade(trade_id)
	for member_id: String in trade.members:
		_send_to_entity.call(member_id, {"type": "trade_completed", "result": _wire_success({
			"trade_id": trade_id, "summary": committed.value,
		})})
	return DomainResultScript.ok({"trade_id": trade_id, "committed": true})


func _cancel(actor_id: String, trade_id: String, reason: String) -> DomainResult:
	var trade := _trade_for_actor(actor_id, trade_id)
	if trade.is_empty(): return _failure(&"trade.missing", "trade session is unavailable")
	_destroy_trade(trade_id)
	for member_id: String in trade.members:
		_send_to_entity.call(member_id, {"type": "trade_cancelled", "result": _wire_success({
			"trade_id": trade_id, "reason": reason,
		})})
	return DomainResultScript.ok({"trade_id": trade_id, "cancelled": true})


func _trade_for_actor(actor_id: String, trade_id: String) -> Dictionary:
	if trade_id.is_empty() or String(_trade_for_entity.get(actor_id, "")) != trade_id:
		return {}
	return _trades.get(trade_id, {})


func _trade_in_same_map(trade: Dictionary) -> bool:
	var members: Array = trade.get("members", [])
	return members.size() == 2 and String(_map_for_entity.call(members[0])) == String(_map_for_entity.call(members[1]))


func _other_member(trade: Dictionary, actor_id: String) -> String:
	for member_id: String in trade.members:
		if member_id != actor_id: return member_id
	return ""


func _unlock_trade(trade: Dictionary) -> void:
	for member_id: String in trade.members:
		trade.offers[member_id].locked = false


func _destroy_trade(trade_id: String) -> void:
	var trade: Dictionary = _trades.get(trade_id, {})
	if trade.is_empty(): return
	for member_id: String in trade.members:
		_trade_for_entity.erase(member_id)
	_trades.erase(trade_id)


func _broadcast_trade(trade_id: String) -> void:
	var snapshot := _trade_snapshot(trade_id)
	var trade: Dictionary = _trades.get(trade_id, {})
	if trade.is_empty(): return
	for member_id: String in trade.members:
		_send_to_entity.call(member_id, {"type": "trade_state", "result": _wire_success({"trade": snapshot})})


func _trade_snapshot(trade_id: String) -> Dictionary:
	var trade: Dictionary = _trades.get(trade_id, {})
	if trade.is_empty(): return {"trade_id": "", "members": [], "offers": {}}
	var offers: Dictionary = {}
	for member_id: String in trade.members:
		var offer: Dictionary = trade.offers[member_id]
		offers[member_id] = {
			"entity_id": member_id,
			"display_name": String(_display_name_for_entity.call(member_id)),
			"items": offer.items.duplicate(true),
			"currency": int(offer.currency),
			"locked": bool(offer.locked),
		}
	return {"trade_id": trade_id, "members": trade.members.duplicate(), "offers": offers}


func _empty_offer() -> Dictionary:
	return {"items": [], "currency": 0, "locked": false, "inventory_revision": -1}


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
	return _failure(&"trade.invalid_payload", "trade command contains an invalid field set")


func _failure(code: StringName, message: String) -> DomainResult:
	return DomainResultScript.failure(code, message)

func _cancel_invites_for_trade_members(member_ids: Array) -> void:
	for invite_id: String in _pending_invites.keys().duplicate():
		var invite: Dictionary = _pending_invites[invite_id]
		var inviter_id := String(invite.inviter_id)
		var target_id := String(invite.target_entity_id)
		if inviter_id not in member_ids and target_id not in member_ids:
			continue
		_pending_invites.erase(invite_id)
		for endpoint_id: String in [inviter_id, target_id]:
			_send_to_entity.call(endpoint_id, {
				"type": "trade_invite_cancelled",
				"result": _wire_success({
					"invite_id": invite_id, "reason": "participant_started_trade",
				}),
			})
