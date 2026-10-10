class_name PartyPanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

var summary: Label
var members: Tree
var invitation_label: Label
var accept_button: Button
var decline_button: Button
var leave_button: Button
var kick_button: Button
var transfer_button: Button
var _party: Dictionary = {}
var _selected_invite_id := ""
var _selected_member_id := ""
var _entity_id := ""


func _ready() -> void:
	build_modern_window(Vector2(380, 425), "队伍")
	summary = make_label("当前没有队伍", Rect2(20, 49, 340, 24))
	members = Tree.new()
	members.position = Vector2(20, 82)
	members.size = Vector2(340, 150)
	members.columns = 3
	members.hide_root = true
	members.column_titles_visible = true
	for column in range(3):
		members.set_column_title(column, ["成员", "状态", "身份"][column])
		members.set_column_custom_minimum_width(column, [170, 80, 90][column])
	content_root.add_child(members)
	members.item_selected.connect(_select_member)
	invitation_label = make_label("没有待处理邀请", Rect2(20, 245, 340, 42))
	invitation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	accept_button = make_button("接受邀请", Rect2(20, 300, 100, 28), _accept_invite)
	decline_button = make_button("拒绝邀请", Rect2(130, 300, 100, 28), _decline_invite)
	leave_button = make_button("离开队伍", Rect2(240, 300, 100, 28), _leave_party)
	kick_button = make_button("移出成员", Rect2(20, 340, 100, 28), _kick_member)
	transfer_button = make_button("转让队长", Rect2(130, 340, 100, 28), _transfer_leader)
	make_button("关闭", Rect2(155, 385, 70, 24), request_close)
	_render()


## 应用服务端队伍事件；窗口只保存展示副本，不修改权威成员关系。
func apply_event(message: Dictionary) -> void:
	var result: Dictionary = message.get("result", {})
	if not bool(result.get("ok", false)):
		return
	var value: Dictionary = result.get("value", {})
	var message_type := String(message.get("type", ""))
	if message_type == "party_removed":
		_party = {}
		_selected_invite_id = ""
	if message_type == "party_invite_cancelled":
		if String(value.get("invite_id", "")) == _selected_invite_id:
			_selected_invite_id = ""
		invitation_label.text = "队伍邀请已失效"
	if message_type != "party_invite" and value.get("party") is Dictionary:
		_party = (value.party as Dictionary).duplicate(true)
		var pending_invites: Array = _party.get("pending_invites", []) if _party.get("pending_invites") is Array else []
		var selected_invite_exists := false
		for pending_invite: Dictionary in pending_invites:
			if String(pending_invite.get("invite_id", "")) == _selected_invite_id:
				selected_invite_exists = true
				break
		if not selected_invite_exists:
			_selected_invite_id = String((pending_invites[0] as Dictionary).get("invite_id", "")) if not pending_invites.is_empty() else ""
			invitation_label.text = "%s 邀请你加入队伍" % String((pending_invites[0] as Dictionary).get("inviter_name", "玩家")) if not pending_invites.is_empty() else "没有待处理邀请"
	if message_type == "party_invite_declined":
		invitation_label.text = "对方拒绝了队伍邀请"
	if message_type in ["party_invite", "party_join_request"]:
		var invite: Dictionary = value.get("invite", {})
		if not invite.is_empty():
			_selected_invite_id = String(invite.get("invite_id", ""))
			var request_type := String(invite.get("request_type", "invite"))
			invitation_label.text = "%s 申请加入队伍" % String(invite.get("inviter_name", "玩家")) \
				if request_type == "join_request" else "%s 邀请你加入队伍" % String(invite.get("inviter_name", "玩家"))
	_render()


func handle_rejection(code: StringName, message: String) -> void:
	if String(code).begins_with("party.") and is_node_ready():
		invitation_label.text = message if not message.is_empty() else String(code)


func apply_player(player: Player) -> void:
	_entity_id = player.entity_id if player != null else ""
	_render()


func _render() -> void:
	if not is_node_ready():
		return
	var party_id := String(_party.get("party_id", ""))
	summary.text = "队伍：%s" % party_id if not party_id.is_empty() else "当前没有队伍"
	members.clear()
	var root := members.create_item()
	var selected_member_exists := false
	for member: Dictionary in _party.get("members", []):
		var member_id := String(member.get("entity_id", ""))
		if member_id == _selected_member_id:
			selected_member_exists = true
		var row := members.create_item(root)
		row.set_text(0, String(member.get("display_name", member.get("entity_id", ""))))
		row.set_text(1, "在线" if bool(member.get("connected", false)) else "离线")
		row.set_text(2, "队长" if member_id == String(_party.get("leader_id", "")) else "队员")
		row.set_metadata(0, member_id)
	if not selected_member_exists:
		_selected_member_id = ""
	accept_button.disabled = _selected_invite_id.is_empty()
	decline_button.disabled = _selected_invite_id.is_empty()
	leave_button.disabled = party_id.is_empty()
	var can_manage := not party_id.is_empty() and String(_party.get("leader_id", "")) == _entity_id \
		and not _selected_member_id.is_empty() and _selected_member_id != _entity_id
	kick_button.disabled = not can_manage
	transfer_button.disabled = not can_manage


func _select_member() -> void:
	var item := members.get_selected()
	_selected_member_id = String(item.get_metadata(0)) if item != null else ""
	var can_manage := not String(_party.get("party_id", "")).is_empty() \
		and String(_party.get("leader_id", "")) == _entity_id \
		and not _selected_member_id.is_empty() and _selected_member_id != _entity_id
	kick_button.disabled = not can_manage
	transfer_button.disabled = not can_manage


func _accept_invite() -> void:
	if _selected_invite_id.is_empty():
		return
	command_requested.emit({"type": "party_respond", "invite_id": _selected_invite_id, "accept": true})
	_selected_invite_id = ""
	_render()


func _decline_invite() -> void:
	if _selected_invite_id.is_empty():
		return
	command_requested.emit({"type": "party_respond", "invite_id": _selected_invite_id, "accept": false})
	_selected_invite_id = ""
	_render()


func _leave_party() -> void:
	if not String(_party.get("party_id", "")).is_empty():
		command_requested.emit({"type": "party_leave"})


func _kick_member() -> void:
	if not _selected_member_id.is_empty():
		command_requested.emit({"type": "party_kick", "target_entity_id": _selected_member_id})


func _transfer_leader() -> void:
	if not _selected_member_id.is_empty():
		command_requested.emit({"type": "party_transfer_leader", "target_entity_id": _selected_member_id})
