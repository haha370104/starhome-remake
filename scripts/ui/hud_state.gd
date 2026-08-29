class_name HudState
extends RefCounted

signal hud_visibility_changed(visible: bool)
signal minimap_size_changed(size_mode: String)
signal minimap_collapsed_changed(collapsed: bool)
signal top_menu_expanded_changed(expanded: bool)
signal shortcut_visibility_changed(visible: bool)
signal shortcut_page_changed(kind: String, page: int)
signal player_position_changed(world_position: Vector2)
signal reserve_energy_changed(current: float, capacity: float)
signal vehicle_health_changed(current: int, capacity: int)
signal working_energy_changed(current: float, capacity: float)
signal selected_action_slot_changed(slot_id: String)
signal tactical_action_changed(action_id: String, count: int)

const TACTICAL_ACTIONS := ["rocket_launcher", "missile", "stealth", "radar"]

var hud_visible := true
var minimap_size := "small"
var minimap_collapsed := false
var selected_action_slot := "energy_cannon"
var tactical_action_id := ""
var tactical_action_count := -1
var top_menu_expanded := true
var function_bar_compact := false
var item_shortcuts: Array[Dictionary] = [{}, {}, {}, {}, {}]
var shortcut_visible := true
var item_shortcut_page := 0
var skill_shortcut_page := 0
var player_position := Vector2.ZERO
var reserve_energy := 10000.0
var reserve_energy_capacity := 10000.0
var vehicle_health := 70
var vehicle_health_capacity := 70
var working_energy := 100.0
var working_energy_capacity := 100.0


## 执行 `set_hud_visible` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_hud_visible(value: bool) -> void:
	if hud_visible == value:
		return
	hud_visible = value
	hud_visibility_changed.emit(value)


## 执行 `set_minimap_size` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_minimap_size(value: String) -> void:
	var normalized := "large" if value == "large" else "small"
	if minimap_size == normalized:
		return
	minimap_size = normalized
	minimap_size_changed.emit(normalized)


## 在大、小两种小地图尺寸模式之间切换。
func toggle_minimap_size() -> void:
	set_minimap_size("large" if minimap_size == "small" else "small")


## 执行 `set_minimap_collapsed` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_minimap_collapsed(value: bool) -> void:
	if minimap_collapsed == value:
		return
	minimap_collapsed = value
	minimap_collapsed_changed.emit(value)


## 翻转小地图的折叠状态。
func toggle_minimap_collapsed() -> void:
	set_minimap_collapsed(not minimap_collapsed)


## 执行 `set_top_menu_expanded` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_top_menu_expanded(value: bool) -> void:
	if top_menu_expanded == value:
		return
	top_menu_expanded = value
	top_menu_expanded_changed.emit(value)


## 翻转顶部菜单的展开状态。
func toggle_top_menu_expanded() -> void:
	set_top_menu_expanded(not top_menu_expanded)


## 执行 `set_shortcut_visible` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_shortcut_visible(value: bool) -> void:
	if shortcut_visible == value:
		return
	shortcut_visible = value
	shortcut_visibility_changed.emit(value)


## 翻转通用快捷栏的可见状态。
func toggle_shortcut_visible() -> void:
	set_shortcut_visible(not shortcut_visible)


## 执行 `set_shortcut_page` 对应的模块操作。
## [param kind] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param page] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：物品与技能页分别保存，避免界面切页时覆盖另一类快捷键状态。
func set_shortcut_page(kind: String, page: int) -> void:
	var normalized := clampi(page, 0, 1)
	if kind == "item":
		if item_shortcut_page == normalized:
			return
		item_shortcut_page = normalized
	elif kind == "skill":
		if skill_shortcut_page == normalized:
			return
		skill_shortcut_page = normalized
	else:
		return
	shortcut_page_changed.emit(kind, normalized)


## 执行 `set_player_position` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_player_position(value: Vector2) -> void:
	player_position = value
	player_position_changed.emit(value)


## 执行 `set_reserve_energy` 对应的模块操作。
## [param current] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param capacity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_reserve_energy(current: float, capacity: float) -> void:
	reserve_energy_capacity = maxf(capacity, 0.0)
	reserve_energy = clampf(current, 0.0, reserve_energy_capacity)
	reserve_energy_changed.emit(reserve_energy, reserve_energy_capacity)


## 执行 `set_vehicle_health` 对应的模块操作。
## [param current] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param capacity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_vehicle_health(current: int, capacity: int) -> void:
	vehicle_health_capacity = maxi(capacity, 0)
	vehicle_health = clampi(current, 0, vehicle_health_capacity)
	vehicle_health_changed.emit(vehicle_health, vehicle_health_capacity)


## 执行 `set_working_energy` 对应的模块操作。
## [param current] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param capacity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_working_energy(current: float, capacity: float) -> void:
	working_energy_capacity = maxf(capacity, 0.0)
	working_energy = clampf(current, 0.0, working_energy_capacity)
	working_energy_changed.emit(working_energy, working_energy_capacity)


## 执行 `set_selected_action_slot` 对应的模块操作。
## [param slot_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_selected_action_slot(slot_id: String) -> void:
	if slot_id != "energy_cannon" and slot_id != tactical_action_id:
		return
	if selected_action_slot == slot_id:
		return
	selected_action_slot = slot_id
	selected_action_slot_changed.emit(slot_id)


## 用当前战车 Location 13 的实际装备替换唯一战术槽。
## [param action_id] 火箭炮、导弹、隐身或雷达；空字符串表示未安装。
## [param count] 可堆叠装备的剩余数量；负数表示不绘制数字。
func set_tactical_action(action_id: String, count := -1) -> void:
	var normalized := action_id if action_id in TACTICAL_ACTIONS else ""
	var normalized_count := maxi(count, -1)
	if tactical_action_id == normalized and tactical_action_count == normalized_count:
		return
	var previous := tactical_action_id
	tactical_action_id = normalized
	tactical_action_count = normalized_count
	if selected_action_slot == previous and selected_action_slot != tactical_action_id:
		set_selected_action_slot("energy_cannon")
	tactical_action_changed.emit(tactical_action_id, tactical_action_count)
