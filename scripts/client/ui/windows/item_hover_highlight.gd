class_name ItemHoverHighlight
extends RefCounted

const HOVER_SHADER := preload("res://scripts/client/ui/windows/item_hover_glow.gdshader")
const LegacyItemTooltipScript := preload(
	"res://scripts/client/ui/windows/legacy_item_tooltip.gd"
)
const GLOW_COLOR := Color("33ff00")
const TOOLTIP_OFFSET := Vector2(10.0, -20.0)
const EXIT_GRACE_SECONDS := 0.1

static var _active_tooltip: Control
static var _active_target: Control
static var _hide_revision := 0


## 给物品命中控件及其实际图像绑定荣耀版绿色发光。
## [param hit_target] 接收鼠标进入/离开的控件。
## [param visual] 应用发光材质的物品图像。
## [param tooltip_text] 面板投影生成的复杂说明文本。
## 返回该物品独占的材质实例，供运行时测试或特殊表现组合使用。
static func bind(
	hit_target: Control,
	visual: CanvasItem,
	tooltip_text: String = "",
) -> ShaderMaterial:
	assert(hit_target != null and visual != null)
	hit_target.tooltip_text = ""
	var material := ShaderMaterial.new()
	material.shader = HOVER_SHADER
	material.set_shader_parameter("glow_color", GLOW_COLOR)
	material.set_shader_parameter("hover_amount", 0.0)
	visual.material = material
	hit_target.mouse_entered.connect(func() -> void:
		set_hovered(material, true)
		_show_tooltip(hit_target, tooltip_text)
	)
	hit_target.mouse_exited.connect(func() -> void:
		set_hovered(material, false)
		_schedule_hide(hit_target)
	)
	hit_target.tree_exiting.connect(func() -> void: _hide_for_target(hit_target))
	return material


## 切换单件物品的悬停参数，不改写拖拽/锁定使用的 modulate。
## [param material] bind 返回的物品独占材质。
## [param hovered] 是否处于鼠标悬停状态。
static func set_hovered(material: ShaderMaterial, hovered: bool) -> void:
	if material != null:
		material.set_shader_parameter("hover_amount", 1.0 if hovered else 0.0)


## 立即显示并定位原版式复杂说明窗。
static func _show_tooltip(target: Control, text: String) -> void:
	if text.is_empty() or target.get_tree() == null:
		return
	_hide_revision += 1
	var host := _tooltip_host(target)
	if _active_tooltip == null or not is_instance_valid(_active_tooltip) \
			or _active_tooltip.get_parent() != host:
		if _active_tooltip != null and is_instance_valid(_active_tooltip):
			_active_tooltip.queue_free()
		_active_tooltip = LegacyItemTooltipScript.new()
		host.add_child(_active_tooltip)
		_active_tooltip.mouse_entered.connect(_keep_tooltip_open)
		_active_tooltip.mouse_exited.connect(_schedule_tooltip_hide)
	_active_target = target
	_active_tooltip.set_content(text)
	_active_tooltip.show()
	_active_tooltip.move_to_front()
	_place_tooltip(target)


## 把说明窗放在鼠标右 10、上 20，并限制在当前视口内。
static func _place_tooltip(target: Control) -> void:
	var viewport_size := target.get_viewport_rect().size
	var tooltip_size: Vector2 = _active_tooltip.get_combined_minimum_size()
	_active_tooltip.size = tooltip_size
	var desired := target.get_viewport().get_mouse_position() + TOOLTIP_OFFSET
	desired.x = clampf(desired.x, 0.0, maxf(0.0, viewport_size.x - tooltip_size.x))
	desired.y = clampf(desired.y, 0.0, maxf(0.0, viewport_size.y - tooltip_size.y))
	_active_tooltip.position = desired


## 查找与面板相同的 CanvasLayer，确保说明窗不会被 HUD 遮住。
static func _tooltip_host(target: Control) -> Node:
	var ancestor: Node = target.get_parent()
	while ancestor != null:
		if ancestor is CanvasLayer:
			return ancestor
		ancestor = ancestor.get_parent()
	return target.get_tree().root


## 离开物品后保留 100ms，允许鼠标跨入说明窗。
static func _schedule_hide(target: Control) -> void:
	if target.get_tree() == null:
		_hide_for_target(target)
		return
	_hide_revision += 1
	var expected_revision := _hide_revision
	target.get_tree().create_timer(EXIT_GRACE_SECONDS).timeout.connect(func() -> void:
		if expected_revision == _hide_revision:
			_hide_if_pointer_left(target)
	)


## 鼠标进入说明窗后取消离开物品产生的待隐藏任务。
static func _keep_tooltip_open() -> void:
	_hide_revision += 1


## 离开说明窗时使用同样的短暂检查，避免边缘抖动。
static func _schedule_tooltip_hide() -> void:
	if _active_target == null or not is_instance_valid(_active_target):
		_hide_active()
		return
	_schedule_hide(_active_target)


## 当鼠标既不在物品也不在说明窗时隐藏说明。
static func _hide_if_pointer_left(target: Control) -> void:
	if _active_target != target or _active_tooltip == null \
			or not is_instance_valid(_active_tooltip):
		return
	var mouse_position := target.get_viewport().get_mouse_position()
	if target.get_global_rect().has_point(mouse_position) \
			or _active_tooltip.get_global_rect().has_point(mouse_position):
		return
	_hide_active()


## 目标销毁时关闭属于它的说明窗。
static func _hide_for_target(target: Control) -> void:
	if _active_target == target:
		_hide_active()


## 隐藏当前全局物品说明窗但保留节点复用。
static func _hide_active() -> void:
	_hide_revision += 1
	_active_target = null
	if _active_tooltip != null and is_instance_valid(_active_tooltip):
		_active_tooltip.hide()


## 提供给运行时测试的当前说明窗只读引用。
static func active_tooltip() -> Control:
	return _active_tooltip if _active_tooltip != null and is_instance_valid(_active_tooltip) else null
