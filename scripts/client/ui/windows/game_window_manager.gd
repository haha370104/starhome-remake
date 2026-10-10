class_name GameWindowManager
extends Control

signal notice_requested(message: String)
signal social_command_requested(command: Dictionary)

const CharacterPanelScript := preload("res://scripts/client/ui/windows/character/character_panel.gd")
const InventoryPanelScript := preload("res://scripts/client/ui/windows/inventory/inventory_panel.gd")
const VehiclePanelScript := preload("res://scripts/client/ui/windows/vehicle/vehicle_equipment_panel.gd")
const SkillLevelPanelScript := preload("res://scripts/client/ui/windows/skills/skill_level_panel.gd")
const WeaponMerchantWindowScript := preload(
	"res://scripts/client/ui/windows/commerce/weapon_merchant_window.gd"
)
const ManufacturingWindowScript := preload(
	"res://scripts/client/ui/windows/manufacturing/manufacturing_window.gd"
)
const SlotMachineWindowScript := preload(
	"res://scripts/client/ui/windows/entertainment/slot_machine_window.gd"
)
const PartyPanelScript := preload("res://scripts/client/ui/windows/navigation/party_panel.gd")
const TradePanelScript := preload("res://scripts/client/ui/windows/navigation/trade_panel.gd")
const ChatPanelScript := preload("res://scripts/client/ui/windows/navigation/chat_panel.gd")
const FriendsPanelScript := preload("res://scripts/client/ui/windows/navigation/friends_panel.gd")
const MailPanelScript := preload("res://scripts/client/ui/windows/navigation/mail_panel.gd")

var character_panel: CharacterPanel
var public_character_panel: CharacterPanel
var inventory_panel: InventoryPanel
var vehicle_panel: VehicleEquipmentPanel
var public_vehicle_panel: VehicleEquipmentPanel
var skill_panel: SkillLevelPanel
var weapon_merchant_window: WeaponMerchantWindow
var manufacturing_window: Control
var slot_machine_window: SlotMachineWindow
var party_window: PartyPanel
var trade_window: TradePanel
var chat_window: ChatPanel
var friends_window: FriendsPanel
var mail_window: MailPanel

var panel_session: PlayerPanelSession
var navigation_windows: Dictionary = {}
var _requested_public_target_by_view: Dictionary = {}


## 创建窗口并订阅外部玩家会话；管理器不拥有玩家状态和命令版本。
## [param session] 生命周期由客户端组合根管理的共享会话。
## 返回窗口是否完成初始化。
func configure(session: PlayerPanelSession) -> bool:
	panel_session = session
	panel_session.bundle_received.connect(_apply_auxiliary_bundle)
	panel_session.panel_state_changed.connect(_apply_panel_state)
	panel_session.journal_changed.connect(_apply_journal_change)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	resized.connect(_clamp_windows)

	character_panel = CharacterPanelScript.new()
	character_panel.name = "CharacterPanel"
	character_panel.position = Vector2(80, 70)
	character_panel.command_requested.connect(panel_session.dispatch)
	character_panel.skill_panel_requested.connect(_toggle_skill_panel)
	character_panel.enhancement_requested.connect(_open_clothing_enhancement)
	_add_window(character_panel)
	public_character_panel = CharacterPanelScript.new()
	public_character_panel.name = "PublicCharacterPanel"
	public_character_panel.read_only = true
	public_character_panel.position = Vector2(100, 90)
	_add_window(public_character_panel)
	inventory_panel = InventoryPanelScript.new()
	inventory_panel.name = "InventoryPanel"
	inventory_panel.position = Vector2(460, 70)
	inventory_panel.command_requested.connect(panel_session.dispatch)
	inventory_panel.enhancement_requested.connect(_open_clothing_enhancement)
	inventory_panel.vehicle_workshop_requested.connect(_open_vehicle_sockets)
	inventory_panel.equipment_processing_requested.connect(_open_equipment_processing)
	inventory_panel.equipment_maintenance_requested.connect(_open_equipment_maintenance)
	inventory_panel.extra_attributes_requested.connect(_open_extra_attributes)
	inventory_panel.equipment_strengthening_requested.connect(_open_equipment_strengthening)
	inventory_panel.armor_refinement_requested.connect(_open_armor_refinement)
	inventory_panel.clothing_improvement_requested.connect(_open_clothing_improvement)
	inventory_panel.equipment_memory_requested.connect(_open_equipment_memory)
	inventory_panel.equipment_dismantle_requested.connect(_open_equipment_dismantle)
	inventory_panel.equipment_forging_requested.connect(_open_equipment_forging)
	inventory_panel.crystal_source_requested.connect(_open_crystal_source)
	inventory_panel.austin_glens_requested.connect(_open_austin_glens)
	inventory_panel.central_requested.connect(_open_central)
	inventory_panel.sama_requested.connect(_open_sama)
	inventory_panel.warehouse_requested.connect(_open_warehouse)
	_add_window(inventory_panel)
	inventory_panel._item_canvas.transfer_requested.connect(_transfer_warehouse_item.bind(false))
	vehicle_panel = VehiclePanelScript.new()
	vehicle_panel.name = "VehicleEquipmentPanel"
	vehicle_panel.position = Vector2(250, 120)
	vehicle_panel.command_requested.connect(panel_session.dispatch)
	_add_window(vehicle_panel)
	public_vehicle_panel = VehiclePanelScript.new()
	public_vehicle_panel.name = "PublicVehicleEquipmentPanel"
	public_vehicle_panel.read_only = true
	public_vehicle_panel.position = Vector2(270, 140)
	_add_window(public_vehicle_panel)
	skill_panel = SkillLevelPanelScript.new()
	skill_panel.name = "SkillLevelPanel"
	skill_panel.position = Vector2(445, 70)
	_add_window(skill_panel)
	weapon_merchant_window = WeaponMerchantWindowScript.new()
	weapon_merchant_window.name = "WeaponMerchantWindow"
	weapon_merchant_window.position = Vector2(170, 80)
	weapon_merchant_window.command_requested.connect(panel_session.dispatch)
	_add_window(weapon_merchant_window)
	manufacturing_window = ManufacturingWindowScript.new()
	manufacturing_window.name = "ManufacturingWindow"
	manufacturing_window.position = Vector2(190, 90)
	manufacturing_window.command_requested.connect(panel_session.dispatch)
	_add_window(manufacturing_window)
	slot_machine_window = SlotMachineWindowScript.new()
	slot_machine_window.name = "SlotMachineWindow"
	slot_machine_window.position = Vector2(240, 100)
	slot_machine_window.command_requested.connect(panel_session.dispatch)
	_add_window(slot_machine_window)
	var navigation_scripts := {
		"crystal_source": preload("res://scripts/client/ui/windows/navigation/crystal_source_panel.gd"),
		"central_controller": preload("res://scripts/client/ui/windows/navigation/central_panel.gd"),
		"sama": preload("res://scripts/client/ui/windows/navigation/sama_panel.gd"),
		"austin_glens": preload("res://scripts/client/ui/windows/navigation/austin_glens_panel.gd"),
		"vehicle_presets": preload("res://scripts/client/ui/windows/navigation/vehicle_loadout_presets_panel.gd"),
		"pve_death_journal": preload("res://scripts/client/ui/windows/navigation/pve_death_journal_panel.gd"),
		"personal_warehouse": preload("res://scripts/client/ui/windows/navigation/personal_warehouse_panel.gd"),
		"scene_players": preload("res://scripts/client/ui/windows/navigation/scene_players_panel.gd"),
		"party": PartyPanelScript,
		"trade": TradePanelScript,
		"chat": ChatPanelScript,
		"friends": FriendsPanelScript,
		"mail": MailPanelScript,
		"missions": preload("res://scripts/client/ui/windows/navigation/mission_journal_panel.gd"),
		"system": preload("res://scripts/client/ui/windows/navigation/system_menu_panel.gd"),
		"premium_shop": preload("res://scripts/client/ui/windows/navigation/premium_shop_panel.gd"),
		"clothing_enhancement": preload("res://scripts/client/ui/windows/navigation/clothing_enhancement_panel.gd"),
		"vehicle_sockets": preload("res://scripts/client/ui/windows/navigation/vehicle_socket_panel.gd"),
		"equipment_processing": preload("res://scripts/client/ui/windows/navigation/equipment_processing_panel.gd"),
		"equipment_maintenance": preload("res://scripts/client/ui/windows/navigation/equipment_maintenance_panel.gd"),
		"extra_attributes": preload("res://scripts/client/ui/windows/navigation/extra_attribute_panel.gd"),
		"equipment_strengthening": preload("res://scripts/client/ui/windows/navigation/equipment_strengthening_panel.gd"),
		"armor_refinement": preload("res://scripts/client/ui/windows/navigation/armor_refinement_panel.gd"),
		"clothing_improvement": preload("res://scripts/client/ui/windows/navigation/clothing_improvement_panel.gd"),
		"equipment_memory": preload("res://scripts/client/ui/windows/navigation/equipment_memory_panel.gd"),
		"equipment_forging": preload("res://scripts/client/ui/windows/navigation/equipment_forging_panel.gd"),
		"equipment_dismantle": preload("res://scripts/client/ui/windows/navigation/equipment_dismantle_panel.gd"),
		"attachment_upgrades": preload("res://scripts/client/ui/windows/navigation/attachment_upgrade_panel.gd"),
		"mercenary": preload("res://scripts/client/ui/windows/navigation/daily_activities_panel.gd"),
		"experience": preload("res://scripts/client/ui/windows/navigation/daily_activities_panel.gd"),
		"smart_assistant": preload("res://scripts/client/ui/windows/navigation/smart_assistant_panel.gd"),
		"achievements": preload("res://scripts/client/ui/windows/navigation/achievements_panel.gd"),
	}
	for action: String in navigation_scripts:
		var window: NavigationWindow = navigation_scripts[action].new()
		if action in ["mercenary", "experience"]:
			window.mode = action
		if action in ["missions", "premium_shop", "mercenary", "experience", "attachment_upgrades", "clothing_enhancement", "vehicle_sockets", "equipment_processing", "equipment_maintenance", "extra_attributes", "equipment_strengthening", "armor_refinement", "clothing_improvement", "equipment_memory", "equipment_dismantle", "equipment_forging"]:
			window.command_requested.connect(panel_session.dispatch)
		if window is EquipmentProcessingPanel:
			window.workshop_requested.connect(_open_workshop)
		if window is CrystalSourcePanel or window is AustinGlensPanel or window is SamaPanel or window is CentralPanel:
			window.command_requested.connect(panel_session.dispatch)
		if window is PersonalWarehousePanel or window is VehicleLoadoutPresetsPanel:
			window.command_requested.connect(panel_session.dispatch)
		window.position = Vector2(120, 70)
		window.notice_requested.connect(notice_requested.emit)
		navigation_windows[action] = window
		_add_window(window)
		if window is PersonalWarehousePanel:
			window.position.x = maxf(0.0, size.x * 0.75 - window.size.x * window.scale.x * 0.5)
			window.item_canvas.transfer_requested.connect(_transfer_warehouse_item.bind(true))
		if window is ScenePlayersPanel:
			window.party_invite_requested.connect(_request_party_invite)
			window.party_apply_requested.connect(_request_party_apply)
			window.trade_invite_requested.connect(_request_trade_invite)
			window.friend_requested.connect(_open_friend_target)
			window.private_chat_requested.connect(_open_private_chat)
			window.chat_requested.connect(_open_chat)
		if window is PartyPanel:
			party_window = window
			window.command_requested.connect(social_command_requested.emit)
		if window is TradePanel:
			trade_window = window
			window.command_requested.connect(social_command_requested.emit)
		if window is ChatPanel:
			chat_window = window
			window.command_requested.connect(social_command_requested.emit)
		if window is FriendsPanel:
			friends_window = window
			window.command_requested.connect(social_command_requested.emit)
			window.private_chat_requested.connect(_open_private_chat)
		if window is MailPanel:
			mail_window = window
			window.command_requested.connect(social_command_requested.emit)
		if window is SystemMenuPanel:
			window.mail_requested.connect(_open_mail)
	navigation_windows["premium_shop"].attachment_upgrade_requested.connect(_open_attachment_upgrades)
	navigation_windows["smart_assistant"].journal_requested.connect(func() -> void: toggle("pve_death_journal"))
	navigation_windows["smart_assistant"].presets_requested.connect(_open_vehicle_presets)
	if panel_session.panel_state().is_ready():
		_apply_panel_state(panel_session.panel_state(), null)
	return true


## 在 GUI 分发前优先交给命中窗口的物品菜单，否则关闭窗口。
## [param event] 视口派发的鼠标或键盘输入事件。
## 设计：只处理最上层窗口并消费点击，物品操作由窗口发布，防止同时触发地图移动。
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return
	var window := _topmost_window_at(mouse_event.position)
	if window == null:
		return
	if not window.handle_context_click(mouse_event.position):
		window.request_close()
	get_viewport().set_input_as_handled()


## 按当前子节点绘制顺序查找命中点的最上层游戏窗口。
## [param viewport_position] 鼠标在视口中的位置。
## 返回命中的窗口；面板外返回 null。
func _topmost_window_at(viewport_position: Vector2) -> DraggableGameWindow:
	for index in range(get_child_count() - 1, -1, -1):
		var child := get_child(index)
		if child is DraggableGameWindow and child.is_visible_in_tree() \
				and child.get_global_rect().has_point(viewport_position):
			return child as DraggableGameWindow
	return null


## 按底栏 action_id 切换对应窗口；玩家三面板已有会话快照时直接复用增量状态。
## [param action_id] 底栏业务动作标识；未知动作不消费。
## 返回动作是否被窗口管理器消费。
func toggle(action_id: String) -> bool:
	var window: Control
	var needs_initial_player_sync := not panel_session.current_player.is_ready()
	match action_id:
		"character": window = character_panel
		"inventory": window = inventory_panel
		"vehicle_equipment": window = vehicle_panel
		_:
			if not navigation_windows.has(action_id):
				return false
			window = navigation_windows[action_id]
	window.visible = not window.visible
	if window.visible:
		if action_id == "system":
			window.position = Vector2(size.x / 2.0 + 349, size.y - 29 - window.size.y)
		if action_id == "premium_shop":
			window.open_shop()
		if action_id in ["mercenary", "experience", "central_controller"]:
			window.open_board()
		window.move_to_front()
		window.call("clamp_to_viewport", size)
		if action_id == "scene_players":
			panel_session.dispatch({"type": "query_scene_players"})
		elif action_id == "party":
			social_command_requested.emit({"type": "query_party"})
		elif action_id == "trade":
			social_command_requested.emit({"type": "query_trade"})
		elif action_id == "friends":
			social_command_requested.emit({"type": "query_friends"})
		elif action_id == "mail" and mail_window != null:
			mail_window.open_board()
		elif action_id in ["character", "inventory", "vehicle_equipment"]:
			if needs_initial_player_sync:
				panel_session.request_full_sync()
		elif action_id not in ["system", "premium_shop", "mercenary", "experience", "smart_assistant", "pve_death_journal", "central_controller", "missions", "achievements", "party", "chat", "friends", "mail"]:
			panel_session.dispatch({"type": "query"})
	return true


## 将场景玩家行的真实实体标识送入组队命令通道。
func _request_party_invite(target_entity_id: String) -> void:
	social_command_requested.emit({"type": "party_invite", "target_entity_id": target_entity_id})


## 将场景玩家行的真实实体标识送入申请入队通道。
func _request_party_apply(target_entity_id: String) -> void:
	social_command_requested.emit({"type": "party_apply", "target_entity_id": target_entity_id})


## 将场景玩家行的真实实体标识送入玩家交易邀请通道。
func _request_trade_invite(target_entity_id: String) -> void:
	social_command_requested.emit({"type": "trade_invite", "target_entity_id": target_entity_id})


## 将世界玩家菜单动作复用到现有社交窗口和服务端命令通道。
func request_player_social_action(
	action_id: String,
	target_entity_id: String,
	display_name: String,
) -> void:
	match action_id:
		"view_character": _request_public_profile(target_entity_id, "character")
		"view_equipment": _request_public_profile(target_entity_id, "vehicle")
		"party_invite": _request_party_invite(target_entity_id)
		"party_apply": _request_party_apply(target_entity_id)
		"trade_invite": _request_trade_invite(target_entity_id)
		"friend": _open_friend_target(target_entity_id, display_name)
		"private_chat": _open_private_chat(target_entity_id, display_name)


func _request_public_profile(target_entity_id: String, view: String) -> void:
	_requested_public_target_by_view[view] = target_entity_id
	if view == "character":
		public_character_panel.hide()
	else:
		public_vehicle_panel.hide()
	panel_session.dispatch({"type": "query_public_player_profile", "target_entity_id": target_entity_id,
		"view": view})


func _open_friend_target(target_entity_id: String, display_name: String) -> void:
	if friends_window == null:
		return
	friends_window.open_add_target(target_entity_id, display_name)
	friends_window.visible = true
	friends_window.move_to_front()
	friends_window.clamp_to_viewport(size)
	social_command_requested.emit({"type": "query_friends"})


## 打开区域聊天窗口，不携带任何客户端猜测的玩家身份。
func _open_chat() -> void:
	if chat_window == null:
		return
	chat_window.open_area()
	chat_window.visible = true
	chat_window.move_to_front()
	chat_window.clamp_to_viewport(size)


## 从场景玩家列表打开指定玩家的私聊频道。
func _open_private_chat(target_entity_id: String, display_name: String) -> void:
	if chat_window == null:
		return
	chat_window.open_private(target_entity_id, display_name)
	chat_window.visible = true
	chat_window.move_to_front()
	chat_window.clamp_to_viewport(size)


func _open_mail(section: String = "mail") -> void:
	if mail_window == null:
		return
	mail_window.open_board(section)
	mail_window.visible = true
	mail_window.move_to_front()
	mail_window.clamp_to_viewport(size)


## 消费服务端组队事件，并在收到邀请时打开队伍窗口。
func apply_social_event(message: Dictionary) -> void:
	if party_window != null:
		party_window.apply_event(message)
	if trade_window != null:
		trade_window.apply_event(message)
	if chat_window != null:
		chat_window.apply_event(message)
	if friends_window != null:
		friends_window.apply_event(message)
	if mail_window != null:
		mail_window.apply_event(message)
	var message_type := String(message.get("type", ""))
	if message_type == "party_invite_cancelled":
		social_command_requested.emit({"type": "query_party"})
	elif message_type == "trade_invite_cancelled":
		social_command_requested.emit({"type": "query_trade"})
	elif message_type == "friend_invite_cancelled":
		social_command_requested.emit({"type": "query_friends"})
	if message_type in ["party_invite", "party_join_request"] and party_window != null:
		_show_social_window(party_window)
	if message_type in ["trade_invite", "trade_state"] and trade_window != null:
		_show_social_window(trade_window)
	if message_type == "social_result":
		var value: Variant = message.get("result", {}).get("value", {})
		if value is Dictionary:
			var trade_value: Variant = value.get("trade", {})
			if trade_value is Dictionary and not String(trade_value.get("trade_id", "")).is_empty():
				_show_social_window(trade_window)
			var party_value: Variant = value.get("party", {})
			var party_invites: Variant = []
			if party_value is Dictionary:
				party_invites = party_value.get("pending_invites", [])
			if party_invites is Array and not party_invites.is_empty():
				_show_social_window(party_window)
			var pending_invites: Variant = value.get("pending_invites", [])
			if pending_invites is Array and not pending_invites.is_empty():
				if value.get("trade") is Dictionary:
					_show_social_window(trade_window)
				elif value.get("friends") is Array:
					_show_social_window(friends_window)
	if message_type == "chat_event" and chat_window != null:
		_show_social_window(chat_window)
	if message_type == "friend_invite" and friends_window != null:
		_show_social_window(friends_window)
	if message_type == "mail_received" and mail_window != null:
		_show_social_window(mail_window)


func _show_social_window(window: Control) -> void:
	if window == null:
		return
	window.visible = true
	window.move_to_front()
	window.call("clamp_to_viewport", size)


## 在重连或地图同步完成后补偿查询社交状态，避免可靠事件断线期间丢失邀请。
func request_social_sync(_sync_id: String) -> void:
	for command: Dictionary in [
		{"type": "query_party"}, {"type": "query_trade"}, {"type": "query_friends"},
			{"type": "query_mailbox", "section": "mail"},
			{"type": "query_mailbox", "section": "leaveword"},
	]:
		social_command_requested.emit(command)
	if chat_window != null:
		chat_window.refresh_history()


## 将会话消息中的名单、商店、制造和任务日志分发到对应窗口。
## [param bundle] 已由玩家会话接收的权威消息；可能只包含某个辅助窗口的数据。
func _apply_auxiliary_bundle(bundle: Dictionary) -> void:
	if bundle.get("public_player_profile") is Dictionary:
		var profile: Dictionary = bundle.public_player_profile
		var view := String(profile.get("view", ""))
		if _requested_public_target_by_view.get(view, "") != String(profile.get("target_entity_id", "")):
			return
		var snapshot: Dictionary = profile.get("snapshot", {})
		var window: DraggableGameWindow
		if view == "character":
			window = public_character_panel
			public_character_panel.apply_snapshot(snapshot)
		elif view == "vehicle":
			window = public_vehicle_panel
			public_vehicle_panel.set_viewed_player_name(String(profile.get("display_name", "")))
			public_vehicle_panel.apply_snapshot(snapshot)
		if window != null:
			window.show()
			window.move_to_front()
			window.clamp_to_viewport(size)
		return
	navigation_windows["vehicle_presets"].apply_bundle(bundle, panel_session.current_player)
	var warehouse: PersonalWarehousePanel = navigation_windows["personal_warehouse"]
	if bundle.get("personal_warehouse") is Dictionary:
		warehouse.apply_snapshot(bundle.personal_warehouse, panel_session.current_player)
	navigation_windows["equipment_maintenance"].apply_maintenance_bundle(bundle)
	navigation_windows["equipment_processing"].apply_processing_bundle(bundle)
	navigation_windows["extra_attributes"].apply_processing_bundle(bundle)
	navigation_windows["equipment_strengthening"].apply_processing_bundle(bundle)
	navigation_windows["armor_refinement"].apply_processing_bundle(bundle)
	navigation_windows["clothing_improvement"].apply_processing_bundle(bundle)
	navigation_windows["equipment_memory"].apply_processing_bundle(bundle)
	navigation_windows["equipment_dismantle"].apply_processing_bundle(bundle)
	navigation_windows["equipment_forging"].apply_processing_bundle(bundle)
	navigation_windows["crystal_source"].apply_processing_bundle(bundle)
	navigation_windows["austin_glens"].apply_processing_bundle(bundle)
	navigation_windows["sama"].apply_processing_bundle(bundle)
	navigation_windows["central_controller"].apply_processing_bundle(bundle)
	navigation_windows["vehicle_sockets"].apply_socket_bundle(bundle)
	navigation_windows["clothing_enhancement"].apply_enhancement_bundle(bundle)
	navigation_windows["attachment_upgrades"].apply_upgrade_bundle(bundle)
	for action: String in ["mercenary", "experience"]:
		navigation_windows[action].apply_activity_bundle(bundle)
	if bundle.get("premium_shop") is Dictionary:
		navigation_windows["premium_shop"].apply_shop_bundle(bundle)
	if bundle.get("scene_players") is Dictionary:
		navigation_windows["scene_players"].apply_snapshot(bundle["scene_players"])
	if weapon_merchant_window != null and bundle.get("commerce") is Dictionary:
		weapon_merchant_window.apply_commerce_bundle(bundle, panel_session.current_player)
	if manufacturing_window != null and bundle.get("manufacturing") is Dictionary:
		manufacturing_window.apply_manufacturing_bundle(bundle)
	if slot_machine_window != null:
		slot_machine_window.apply_slot_bundle(bundle)
	if bundle.get("mission_journal") is Array:
		navigation_windows["missions"].apply_entries(bundle["mission_journal"])


## 从智脑进入整套换装窗口，沿用同一玩家会话和窗口堆叠上下文。
func _open_vehicle_presets() -> void:
	var window: VehicleLoadoutPresetsPanel = navigation_windows["vehicle_presets"]
	window.open_board()
	window.move_to_front()
	window.clamp_to_viewport(size)


## 从商城进入强化窗口，使用共享会话查询权威材料及装备状态。
func _open_attachment_upgrades() -> void:
	var window: NavigationWindow = navigation_windows["attachment_upgrades"]
	window.show()
	window.move_to_front()
	window.clamp_to_viewport(size)
	window.open_board()


## 从背包进入个人仓库，地点、柜号和库存都重新查询服务端。
func _open_warehouse() -> void:
	var window: PersonalWarehousePanel = navigation_windows["personal_warehouse"]
	window.show()
	window.move_to_front()
	window.clamp_to_viewport(size)
	window.open_board()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN: mouse_filter = Control.MOUSE_FILTER_PASS
	elif what == NOTIFICATION_DRAG_END: mouse_filter = Control.MOUSE_FILTER_IGNORE


func _transfer_warehouse_item(instance_id: String, source: InventoryCanvas, position: Vector2i, deposit: bool) -> void:
	var warehouse: PersonalWarehousePanel = navigation_windows["personal_warehouse"]
	if inventory_panel.visible and warehouse.visible \
		and source == (inventory_panel._item_canvas if deposit else warehouse.item_canvas):
		warehouse.transfer_item(instance_id, deposit, position)


## 用会话的同事务投影同步人物、战车、背包和技能展示。
## [param player] 已完成权威快照还原的当前玩家。
func _apply_panel_state(state: PanelState, change: Variant) -> void:
	var player := panel_session.current_player
	if change == null:
		character_panel.apply_snapshot(state.slice("character"))
		inventory_panel.apply_inventory(player.inventory)
		inventory_panel.apply_food_status(player.food_status)
		character_panel.set_inventory_revision(state.domain_revision("inventory"))
		vehicle_panel.set_inventory_revision(state.domain_revision("inventory"))
		weapon_merchant_window.apply_inventory_state(player)
		party_window.apply_player(player)
		trade_window.apply_player(player)
		chat_window.apply_player(player)
		vehicle_panel.apply_snapshot(state.slice("vehicle"))
		skill_panel.apply_skills(state.slice("character").get("skills", []))
		navigation_windows["achievements"].apply_achievements(player.achievements)
		if manufacturing_window.visible: manufacturing_window.request_refresh()
		return
	var player_change := change as PlayerChange
	if player_change == null: return
	_apply_panel_delta(state, player, player_change)


## 仅按 PlayerChange 涉及的领域刷新窗口，技能经验不重建人物或战车视图。
func _apply_panel_delta(state: PanelState, player: Player, change: PlayerChange) -> void:
	if change.inventory_revision >= 0:
		var item_ids: Array[String] = []
		for item: Dictionary in change.items: item_ids.append(String(item.instance_id))
		for identity: String in change.removed_items: item_ids.append(identity)
		inventory_panel.apply_inventory_change(player.inventory, item_ids)
		slot_machine_window.set_balance(player.inventory.currency)
		character_panel.set_inventory_revision(player.inventory.revision)
		vehicle_panel.set_inventory_revision(player.inventory.revision)
		weapon_merchant_window.apply_inventory_state(player)
		party_window.apply_player(player)
		trade_window.apply_player(player)
		navigation_windows["vehicle_presets"].refresh_player(player)
	character_panel.apply_progression(player.level, player.revision)
	if not change.character.is_empty():
		character_panel.apply_snapshot(state.slice("character"))
		skill_panel.apply_skills(state.slice("character").get("skills", []))
	if not change.vehicle.is_empty():
		vehicle_panel.apply_snapshot(state.slice("vehicle"))
		navigation_windows["vehicle_presets"].refresh_player(player)
	if not change.presets.is_empty():
		navigation_windows["vehicle_presets"].apply_bundle({"vehicle_presets": change.presets,
		"preset_server_time": change.preset_server_time}, player)
	if not change.food.is_empty(): inventory_panel.apply_food_status(player.food_status)
	if change.character_health >= 0: character_panel.apply_health(player.health, player.max_health)
	if not change.skills.is_empty(): skill_panel.apply_changes(change.skills)
	if not change.achievements.is_empty(): navigation_windows["achievements"].apply_changes(player.achievements, change.achievements)
	if not change.daily.is_empty():
		for action: String in ["mercenary", "experience"]:
			navigation_windows[action].apply_activity_bundle({"daily_activities": change.daily,
				"inventory": {"revision": player.inventory.revision}})
	if change.attributes_changed: vehicle_panel.apply_stats(player.calculate_vehicle_stats())
	if not change.vehicle_stats.is_empty(): vehicle_panel.apply_stats(change.vehicle_stats)


## 打开武器商人的购买、出售或任务窗口，并拉取同一事务快照。
## [param mode] buy、sell 或 task。
## [param merchant_id] NPC 对应的普通或特殊武器商人标识。
func open_weapon_merchant(mode: String, merchant_id := "weapon_merchant") -> void:
	weapon_merchant_window.open_mode(mode, merchant_id)
	weapon_merchant_window.clamp_to_viewport(size)


## 打开地图机器对应的裁缝或烹饪窗口并请求权威配方。
## [param station_id] tailoring 或 cooking。
func open_manufacturing(station_id: String) -> void:
	manufacturing_window.open_station(station_id)
	manufacturing_window.clamp_to_viewport(size)


## 打开所选娱乐大厅游戏机。
## [param machine_id] 地图机器的稳定标识。
func open_slot_machine(machine_id: String) -> void:
	slot_machine_window.open_machine(machine_id)
	slot_machine_window.clamp_to_viewport(size)


## 切图时收起当前机器，拒绝沿用旧地点的交互窗口。
func close_slot_machine() -> void:
	slot_machine_window.hide()


## 把与当前老虎机操作有关的权威拒绝原因交还窗口。
## [param code] 服务端错误码。[param message] 服务端说明。
func on_command_rejected(code: StringName, message: String) -> void:
	slot_machine_window.handle_rejection(code, message); navigation_windows["personal_warehouse"].handle_rejection(code, message)
	if party_window != null:
		party_window.handle_rejection(code, message)
	if trade_window != null:
		trade_window.handle_rejection(code, message)
	if chat_window != null:
		chat_window.handle_rejection(code, message)
	if friends_window != null:
		friends_window.handle_rejection(code, message)
	if mail_window != null:
		mail_window.handle_rejection(code, message)


## 切换非模态技能等级窗口并保持其处于可见区域。
## 设计：技能窗与人物、背包、战车窗口同属窗口管理器，窗外输入继续交给地图。
func _toggle_skill_panel() -> void:
	skill_panel.visible = not skill_panel.visible
	if skill_panel.visible:
		skill_panel.move_to_front()
		skill_panel.clamp_to_viewport(size)
		panel_session.request_full_sync()


## 将新窗口加入管理层并建立关闭语义。
## [param window] DraggableGameWindow 子类。
func _add_window(window: Control) -> void:
	window.visible = false
	window.close_requested.connect(func() -> void: window.visible = false)
	add_child(window)


## 视口变化时把所有窗口重新限制在可见区域。
func _clamp_windows() -> void:
	for window: Control in navigation_windows.values():
		window.call("clamp_to_viewport", size)
	for window: Control in [
		character_panel, public_character_panel, inventory_panel, vehicle_panel, public_vehicle_panel,
		skill_panel, weapon_merchant_window,
		manufacturing_window, slot_machine_window,
	]:
		if window != null:
			window.call("clamp_to_viewport", size)


## 从人物面板或背包进入人物强化，窗口只提交选择意图。
## [param id] 可选的装备或材料实例。
## [param is_stone] 实例是否为强化材料。
func _open_clothing_enhancement(id: String = "", is_stone: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["clothing_enhancement"], size, id, is_stone)


## 从背包装备或晶石进入独立加工窗口。
## [param id] 可选实例身份。
## [param is_material] 是否定位到材料。
func _open_vehicle_sockets(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["vehicle_sockets"], size, id, is_material)


## 从背包进入普通装备加工，不混用接合器强化规则。
## [param id] 装备或材料实例。
## [param is_material] 是否为材料。
func _open_equipment_processing(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["equipment_processing"], size, id, is_material)


## 从装备或速修工具进入独立维护页。
## [param id] 目标实例。
## [param is_material] 是否为速修工具。
func _open_equipment_maintenance(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["equipment_maintenance"], size, id, is_material)


## 从合资格装备或萤石/耀石进入独立额外属性窗口。
## [param id] 目标实例。
## [param is_material] 是否为材料。
func _open_extra_attributes(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["extra_attributes"], size, id, is_material)


## 从装备或强化石进入十星强化窗口。
## [param id] 初始实例。
## [param is_material] 是否为材料。
func _open_equipment_strengthening(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["equipment_strengthening"], size, id, is_material)


## 从护甲或精工材料的背包右键定位窗口。
## [param id] 实例标识。
## [param is_material] 是否选择材料。
func _open_armor_refinement(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["armor_refinement"], size, id, is_material)


## 从时装或仿生纤维定位原版改良窗口。
## [param id] 目标实例。
## [param is_material] 是否为纤维。
func _open_clothing_improvement(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["clothing_improvement"], size, id, is_material)


## 从战车装备或模块进入成长提取转移窗口。
## [param id] 当前实例。
## [param is_material] 是否为记忆模块。
func _open_equipment_memory(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["equipment_memory"], size, id, is_material)


## 从共享加工项目入口打开已注册的独立窗口。
## [param action] 加工目录内的窗口动作。
func _open_workshop(action: String) -> void:
	if EquipmentWorkshopNavigation.PROJECTS.has(action):
		EquipmentWorkshopNavigation.focus(navigation_windows[action], size, "", false)


## 从背包定位拆解预览，实际后果确认由面板负责。
## [param id] 当前装备实例。
## [param is_material] 通用入口参数，拆解没有输入材料。
func _open_equipment_dismantle(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["equipment_dismantle"], size, id, is_material)


## 从装备或芯片定位锻造预览。
## [param id] 实例身份。
## [param is_material] 是否选择芯片。
func _open_equipment_forging(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["equipment_forging"], size, id, is_material)


## 从背包定位晶源体或专属核心，窗口之间只传操作意图。
## [param id] 物品身份。[param is_material] 是否为核心材料。
func _open_crystal_source(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["crystal_source"], size, id, is_material)


## 从背包打开奥斯格兰成长，复用工坊导航而不在大厅复制规则。
## [param id] 装备身份。[param is_material] 材料选择标识。
func _open_austin_glens(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["austin_glens"], size, id, is_material)


## 打开撒玛加工并定位右键选择的实例，保持窗口各自堆叠上下文。
## [param id] 背包目标身份。[param is_material] 是否将其作为转出来源。
func _open_sama(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["sama"], size, id, is_material)


## 从背包或工坊定位中枢模块及圣焱装备。
## [param id] 物品身份。[param is_material] 通用导航标记。
func _open_central(id: String = "", is_material: bool = false) -> void:
	EquipmentWorkshopNavigation.focus(navigation_windows["central_controller"], size, id, is_material)


## 单独刷新任务进度，保持其他导航窗口的状态。
## [param entries] 当前完整任务日志视图。
func _apply_journal_change(entries: Array) -> void:
	navigation_windows["missions"].apply_entries(entries)
