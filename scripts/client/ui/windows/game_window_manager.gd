class_name GameWindowManager
extends Control

signal notice_requested(message: String)

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

var character_panel: CharacterPanel
var inventory_panel: InventoryPanel
var vehicle_panel: VehicleEquipmentPanel
var skill_panel: SkillLevelPanel
var weapon_merchant_window: WeaponMerchantWindow
var manufacturing_window: Control

var panel_session: PlayerPanelSession
var navigation_windows: Dictionary = {}


## 创建窗口并订阅外部玩家会话；管理器不拥有玩家状态和命令版本。
## [param session] 生命周期由客户端组合根管理的共享会话。
## 返回窗口是否完成初始化。
func configure(session: PlayerPanelSession) -> bool:
	panel_session = session
	panel_session.bundle_received.connect(_apply_auxiliary_bundle)
	panel_session.player_changed.connect(_apply_player)
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
	_add_window(inventory_panel)
	vehicle_panel = VehiclePanelScript.new()
	vehicle_panel.name = "VehicleEquipmentPanel"
	vehicle_panel.position = Vector2(250, 120)
	vehicle_panel.command_requested.connect(panel_session.dispatch)
	_add_window(vehicle_panel)
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
	var navigation_scripts := {
		"scene_players": preload("res://scripts/client/ui/windows/navigation/scene_players_panel.gd"),
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
		if action in ["premium_shop", "mercenary", "experience", "attachment_upgrades", "clothing_enhancement", "vehicle_sockets", "equipment_processing", "equipment_maintenance", "extra_attributes", "equipment_strengthening", "armor_refinement", "clothing_improvement", "equipment_memory"]:
			window.command_requested.connect(panel_session.dispatch)
		if window is EquipmentProcessingPanel:
			window.workshop_requested.connect(_open_workshop)
		window.position = Vector2(120, 70)
		window.notice_requested.connect(notice_requested.emit)
		navigation_windows[action] = window
		_add_window(window)
	navigation_windows["premium_shop"].attachment_upgrade_requested.connect(_open_attachment_upgrades)
	var refresh := Timer.new()
	refresh.wait_time = 2.0
	refresh.timeout.connect(_refresh_navigation)
	add_child(refresh)
	refresh.start()

	if not panel_session.snapshot_bundle().is_empty():
		_apply_player(panel_session.current_player)
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


## 按底栏 action_id 切换对应窗口，并在打开时拉取权威快照。
## [param action_id] 底栏业务动作标识；未知动作不消费。
## 返回动作是否被窗口管理器消费。
func toggle(action_id: String) -> bool:
	var window: Control
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
			window.position = Vector2(size.x / 2.0 + 235, size.y - 29 - window.size.y)
		if action_id == "premium_shop":
			window.open_shop()
		if action_id in ["mercenary", "experience"]:
			window.open_board()
		window.move_to_front()
		window.call("clamp_to_viewport", size)
		if action_id == "scene_players":
			panel_session.dispatch({"type": "query_scene_players"})
		elif action_id not in ["system", "premium_shop", "mercenary", "experience", "smart_assistant"]:
			panel_session.dispatch({"type": "query"})
	return true


## 仅在用户列表或任务日志可见时刷新只读查询，关闭窗口不产生轮询。
func _refresh_navigation() -> void:
	if navigation_windows["attachment_upgrades"].visible:
		panel_session.dispatch({"type": "query_attachment_upgrades"})
	if navigation_windows["mercenary"].visible or navigation_windows["experience"].visible:
		panel_session.dispatch({"type": "query_daily_activities"})
	if navigation_windows["scene_players"].visible:
		panel_session.dispatch({"type": "query_scene_players"})
	if navigation_windows["missions"].visible or navigation_windows["achievements"].visible:
		panel_session.dispatch({"type": "query"})


## 将会话消息中的名单、商店、制造和任务日志分发到对应窗口。
## [param bundle] 已由玩家会话接收的权威消息；可能只包含某个辅助窗口的数据。
func _apply_auxiliary_bundle(bundle: Dictionary) -> void:
	navigation_windows["equipment_maintenance"].apply_maintenance_bundle(bundle)
	navigation_windows["equipment_processing"].apply_processing_bundle(bundle)
	navigation_windows["extra_attributes"].apply_processing_bundle(bundle)
	navigation_windows["equipment_strengthening"].apply_processing_bundle(bundle)
	navigation_windows["armor_refinement"].apply_processing_bundle(bundle)
	navigation_windows["clothing_improvement"].apply_processing_bundle(bundle)
	navigation_windows["equipment_memory"].apply_processing_bundle(bundle)
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
		weapon_merchant_window.apply_commerce_bundle(bundle)
	if manufacturing_window != null and bundle.get("manufacturing") is Dictionary:
		manufacturing_window.apply_manufacturing_bundle(bundle)
	if bundle.get("mission_journal") is Array:
		navigation_windows["missions"].apply_entries(bundle["mission_journal"])


## 从商城进入强化窗口，使用共享会话查询权威材料及装备状态。
func _open_attachment_upgrades() -> void:
	var window: NavigationWindow = navigation_windows["attachment_upgrades"]
	window.show()
	window.move_to_front()
	window.clamp_to_viewport(size)
	window.open_board()


## 用会话的同事务投影同步人物、战车、背包和技能展示。
## [param player] 已完成权威快照还原的当前玩家。
func _apply_player(player: Player) -> void:
	var bundle := panel_session.snapshot_bundle()
	character_panel.apply_snapshot(bundle["character"])
	inventory_panel.apply_inventory(player.inventory)
	inventory_panel.apply_food_status(player.food_status)
	character_panel.set_inventory_revision(int(bundle["inventory"].get("revision", -1)))
	vehicle_panel.set_inventory_revision(int(bundle["inventory"].get("revision", -1)))
	vehicle_panel.apply_snapshot(bundle["vehicle"])
	skill_panel.apply_skills(bundle["character"].get("skills", []))
	navigation_windows["achievements"].apply_snapshot(player.achievements.snapshot())


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


## 切换非模态技能等级窗口并保持其处于可见区域。
## 设计：技能窗与人物、背包、战车窗口同属窗口管理器，窗外输入继续交给地图。
func _toggle_skill_panel() -> void:
	skill_panel.visible = not skill_panel.visible
	if skill_panel.visible:
		skill_panel.move_to_front()
		skill_panel.clamp_to_viewport(size)
		panel_session.dispatch({"type": "query"})


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
		character_panel, inventory_panel, vehicle_panel, skill_panel, weapon_merchant_window,
		manufacturing_window,
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
