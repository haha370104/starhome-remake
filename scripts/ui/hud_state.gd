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
signal selected_action_slot_changed(slot_id: String)

var hud_visible := true
var minimap_size := "small"
var minimap_collapsed := false
var selected_action_slot := "energy_cannon"
var top_menu_expanded := true
var function_bar_compact := false
var item_shortcuts: Array[Dictionary] = [{}, {}, {}, {}, {}]
var shortcut_visible := true
var item_shortcut_page := 0
var skill_shortcut_page := 0
var player_position := Vector2.ZERO
var reserve_energy := 10000.0
var reserve_energy_capacity := 10000.0


## 设置 HUD 的整体可见状态，并在状态改变时广播。[param value] 为目标可见状态。
func set_hud_visible(value: bool) -> void:
	if hud_visible == value:
		return
	hud_visible = value
	hud_visibility_changed.emit(value)


## 切换小地图尺寸模式，并把非法的 [param value] 归一化为 `small`。
func set_minimap_size(value: String) -> void:
	var normalized := "large" if value == "large" else "small"
	if minimap_size == normalized:
		return
	minimap_size = normalized
	minimap_size_changed.emit(normalized)


## 在大、小两种小地图尺寸模式之间切换。
func toggle_minimap_size() -> void:
	set_minimap_size("large" if minimap_size == "small" else "small")


## 设置小地图是否折叠；[param value] 为目标折叠状态。
func set_minimap_collapsed(value: bool) -> void:
	if minimap_collapsed == value:
		return
	minimap_collapsed = value
	minimap_collapsed_changed.emit(value)


## 翻转小地图的折叠状态。
func toggle_minimap_collapsed() -> void:
	set_minimap_collapsed(not minimap_collapsed)


## 设置顶部菜单是否展开；[param value] 为目标展开状态。
func set_top_menu_expanded(value: bool) -> void:
	if top_menu_expanded == value:
		return
	top_menu_expanded = value
	top_menu_expanded_changed.emit(value)


## 翻转顶部菜单的展开状态。
func toggle_top_menu_expanded() -> void:
	set_top_menu_expanded(not top_menu_expanded)


## 设置通用快捷栏是否可见；[param value] 为目标可见状态。
func set_shortcut_visible(value: bool) -> void:
	if shortcut_visible == value:
		return
	shortcut_visible = value
	shortcut_visibility_changed.emit(value)


## 翻转通用快捷栏的可见状态。
func toggle_shortcut_visible() -> void:
	set_shortcut_visible(not shortcut_visible)


## 设置 [param kind] 所指快捷栏的 [param page] 页，并把页码限制在可用范围。
## Design: 物品与技能页分别保存，避免界面切页时覆盖另一类快捷键状态。
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


## 更新玩家世界坐标为 [param value]，供小地图等 HUD 消费。
func set_player_position(value: Vector2) -> void:
	player_position = value
	player_position_changed.emit(value)


## 更新储备能量；[param current] 会按 [param capacity] 归一化并限制在有效区间。
func set_reserve_energy(current: float, capacity: float) -> void:
	reserve_energy_capacity = maxf(capacity, 0.0)
	reserve_energy = clampf(current, 0.0, reserve_energy_capacity)
	reserve_energy_changed.emit(reserve_energy, reserve_energy_capacity)


## 将当前动作槽设为 [param slot_id]，并仅在值变化时广播。
func set_selected_action_slot(slot_id: String) -> void:
	if selected_action_slot == slot_id:
		return
	selected_action_slot = slot_id
	selected_action_slot_changed.emit(slot_id)
