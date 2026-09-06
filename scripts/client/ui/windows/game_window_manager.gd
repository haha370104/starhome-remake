class_name GameWindowManager
extends Control

signal command_dispatched(command: Dictionary)
signal current_player_changed(player: Player)

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
const CurrentPlayerScript := preload("res://scripts/client/state/current_player.gd")

var character_panel: CharacterPanel
var inventory_panel: InventoryPanel
var vehicle_panel: VehicleEquipmentPanel
var skill_panel: SkillLevelPanel
var weapon_merchant_window: WeaponMerchantWindow
var manufacturing_window: Control

## 【重点 Review】当前登录人物的客户端只读全局投影；业务 UI 必须从这里读取同版本人物与战车状态。
## 设计：属性值仍由权威服务器产生，本对象只负责跨面板共享与信号通知。
var current_player: CurrentPlayer

var _dispatcher: Callable
var _bundle: Dictionary = {}


## 创建三个单例窗口并绑定统一客户端会话。
## [param dispatcher] 向客户端会话提交命令的回调。
## [param item_catalog] 可选的共享物品目录；场景与背包借此消费同一套定义。
## 返回初始化是否成功。
## 设计：管理器只负责窗口生命周期和成组快照，不感知 ENet 或进程内传输。
func configure(
	dispatcher: Callable,
	item_catalog: ItemCatalog = null,
) -> bool:
	_dispatcher = dispatcher
	current_player = CurrentPlayerScript.new(item_catalog)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	resized.connect(_clamp_windows)

	character_panel = CharacterPanelScript.new()
	character_panel.name = "CharacterPanel"
	character_panel.position = Vector2(80, 70)
	character_panel.command_requested.connect(_dispatch)
	character_panel.skill_panel_requested.connect(_toggle_skill_panel)
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
	skill_panel = SkillLevelPanelScript.new()
	skill_panel.name = "SkillLevelPanel"
	skill_panel.position = Vector2(445, 70)
	_add_window(skill_panel)
	weapon_merchant_window = WeaponMerchantWindowScript.new()
	weapon_merchant_window.name = "WeaponMerchantWindow"
	weapon_merchant_window.position = Vector2(170, 80)
	weapon_merchant_window.command_requested.connect(_dispatch)
	_add_window(weapon_merchant_window)
	manufacturing_window = ManufacturingWindowScript.new()
	manufacturing_window.name = "ManufacturingWindow"
	manufacturing_window.position = Vector2(190, 90)
	manufacturing_window.command_requested.connect(_dispatch)
	_add_window(manufacturing_window)

	return true


## 在 GUI 分发前处理右键关闭，避免物品控件的 STOP 过滤吞掉事件。
## [param event] 视口派发的鼠标或键盘输入事件。
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
	if weapon_merchant_window != null and bundle.get("commerce") is Dictionary:
		weapon_merchant_window.apply_commerce_bundle(bundle)
	if manufacturing_window != null and bundle.get("manufacturing") is Dictionary:
		manufacturing_window.apply_manufacturing_bundle(bundle)
	if current_player == null or not current_player.apply_bundle(bundle):
		return
	_bundle = current_player.snapshot_bundle()
	character_panel.apply_snapshot(_bundle["character"])
	inventory_panel.apply_inventory(current_player.inventory)
	character_panel.set_inventory_revision(int(_bundle["inventory"].get("revision", -1)))
	vehicle_panel.set_inventory_revision(int(_bundle["inventory"].get("revision", -1)))
	vehicle_panel.apply_snapshot(_bundle["vehicle"])
	skill_panel.apply_skills(_bundle["character"].get("skills", []))
	current_player_changed.emit(current_player)


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
		_dispatch({"type": "query"})


## 将面板命令补全双 revision 后发送到所选权威边界。
## [param command] 面板产生的纯操作意图。
func _dispatch(command: Dictionary) -> void:
	var payload := command.duplicate(true)
	if payload.erase("requires_loadout_revision") and _bundle.get("vehicle") is Dictionary:
		payload["loadout_revision"] = int(_bundle["vehicle"].get("revision", -1))
	if payload.erase("requires_state_revision"):
		payload["state_revision"] = int(_bundle.get("transaction_revision", -1))
	command_dispatched.emit(payload.duplicate(true))
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
	for window: Control in [
		character_panel, inventory_panel, vehicle_panel, skill_panel, weapon_merchant_window,
		manufacturing_window,
	]:
		if window != null:
			window.call("clamp_to_viewport", size)
