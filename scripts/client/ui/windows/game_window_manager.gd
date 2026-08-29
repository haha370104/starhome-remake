class_name GameWindowManager
extends Control

signal command_dispatched(command: Dictionary)
signal current_player_changed(player: Player)

const CharacterPanelScript := preload("res://scripts/client/ui/windows/character/character_panel.gd")
const InventoryPanelScript := preload("res://scripts/client/ui/windows/inventory/inventory_panel.gd")
const VehiclePanelScript := preload("res://scripts/client/ui/windows/vehicle/vehicle_equipment_panel.gd")
const OfflineAuthorityScript := preload("res://scripts/client/debug/offline_player_panel_authority.gd")
const CurrentPlayerScript := preload("res://scripts/client/state/current_player.gd")
const DomainResult := preload("res://scripts/core/domain_result.gd")

var character_panel: CharacterPanel
var inventory_panel: InventoryPanel
var vehicle_panel: VehicleEquipmentPanel

## 【重点 Review】当前登录人物的客户端只读全局投影；业务 UI 必须从这里读取同版本人物与战车状态。
## 设计：属性值仍由权威服务器产生，本对象只负责跨面板共享与信号通知。
var current_player: CurrentPlayer

var _dispatcher: Callable
var _offline_authority: OfflinePlayerPanelAuthority
var _bundle: Dictionary = {}


## 创建三个单例窗口并绑定真实网络或显式离线调试边界。
## [param dispatcher] 正式模式下向客户端会话提交命令的回调。
## [param offline_debug_enabled] 是否使用复用服务端规则的内存调试权威。
## 返回初始化是否成功。
## 设计：管理器只负责窗口生命周期和成组快照，不实现背包或装备规则。
func configure(dispatcher: Callable, offline_debug_enabled: bool) -> bool:
	_dispatcher = dispatcher
	current_player = CurrentPlayerScript.new()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	resized.connect(_clamp_windows)

	character_panel = CharacterPanelScript.new()
	character_panel.name = "CharacterPanel"
	character_panel.position = Vector2(80, 70)
	character_panel.command_requested.connect(_dispatch)
	_add_window(character_panel)
	inventory_panel = InventoryPanelScript.new()
	inventory_panel.name = "InventoryPanel"
	inventory_panel.position = Vector2(460, 70)
	inventory_panel.command_requested.connect(_dispatch)
	_add_window(inventory_panel)
	vehicle_panel = VehiclePanelScript.new()
	vehicle_panel.name = "VehicleEquipmentPanel"
	vehicle_panel.position = Vector2(250, 120)
	vehicle_panel.command_requested.connect(_dispatch)
	_add_window(vehicle_panel)

	if offline_debug_enabled:
		_offline_authority = OfflineAuthorityScript.new()
		var initialized := _offline_authority.initialize()
		if not initialized.is_ok:
			push_error("Offline player panel authority failed: %s" % initialized.error_message)
			return false
		_dispatch({"type": "query"})
	return true


## 在 GUI 分发前处理右键关闭，避免物品控件的 STOP 过滤吞掉事件。
## 设计：窗口管理器只关闭鼠标命中的最上层窗口，并标记事件已处理，防止同时触发地图移动。
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return
	var window := _topmost_window_at(mouse_event.position)
	if window == null:
		return
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
## [param action_id] character、inventory 或 vehicle_equipment。
## 返回动作是否被窗口管理器消费。
func toggle(action_id: String) -> bool:
	var window: Control
	match action_id:
		"character": window = character_panel
		"inventory": window = inventory_panel
		"vehicle_equipment": window = vehicle_panel
		_: return false
	window.visible = not window.visible
	if window.visible:
		window.move_to_front()
		window.call("clamp_to_viewport", size)
		_dispatch({"type": "query"})
	return true


## 原子应用服务端返回的三面板快照。
## [param bundle] 含 character、inventory、vehicle 与 transaction_revision 的快照组。
func apply_bundle(bundle: Dictionary) -> void:
	if current_player == null or not current_player.apply_bundle(bundle):
		return
	_bundle = current_player.snapshot_bundle()
	character_panel.apply_snapshot(_bundle["character"])
	inventory_panel.apply_snapshot(_bundle["inventory"])
	character_panel.set_inventory_revision(int(_bundle["inventory"].get("revision", -1)))
	vehicle_panel.set_inventory_revision(int(_bundle["inventory"].get("revision", -1)))
	vehicle_panel.apply_snapshot(_bundle["vehicle"])
	current_player_changed.emit(current_player)


## 在显式离线调试中把战斗掉落交给正式面板权威规则入包。
## [param loot] 离线战斗模块预检通过的掉落 DTO。
## 返回入包后的三面板快照或容量、布局、目录错误。
## 设计：线上流程不会调用该入口；正式服务器仍在单一服务端事务内完成入包和持久化。
func grant_offline_loot(loot: Dictionary):
	if _offline_authority == null:
		return DomainResult.failure(&"loot.offline_unavailable", "offline panel authority is unavailable")
	var result = _offline_authority.grant_loot(loot)
	if result.is_ok:
		apply_bundle(result.value)
	return result


## 将面板命令补全双 revision 后发送到所选权威边界。
## [param command] 面板产生的纯操作意图。
func _dispatch(command: Dictionary) -> void:
	var payload := command.duplicate(true)
	if payload.erase("requires_loadout_revision") and _bundle.get("vehicle") is Dictionary:
		payload["loadout_revision"] = int(_bundle["vehicle"].get("revision", -1))
	if payload.erase("requires_state_revision"):
		payload["state_revision"] = int(_bundle.get("transaction_revision", -1))
	command_dispatched.emit(payload.duplicate(true))
	if _offline_authority != null:
		var offline_result := _offline_authority.execute(payload)
		if offline_result.is_ok:
			apply_bundle(offline_result.value)
		else:
			push_warning("Offline panel command rejected [%s]: %s" % [
				offline_result.error_code, offline_result.error_message,
			])
		return
	if _dispatcher.is_valid():
		_dispatcher.call(payload)


## 将新窗口加入管理层并建立关闭语义。
## [param window] DraggableGameWindow 子类。
func _add_window(window: Control) -> void:
	window.visible = false
	window.close_requested.connect(func() -> void: window.visible = false)
	add_child(window)


## 视口变化时把所有窗口重新限制在可见区域。
func _clamp_windows() -> void:
	for window: Control in [character_panel, inventory_panel, vehicle_panel]:
		if window != null:
			window.call("clamp_to_viewport", size)
