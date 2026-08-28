class_name ItemHoverHighlight
extends RefCounted

const HOVER_SHADER := preload("res://scripts/client/ui/windows/item_hover_glow.gdshader")
const GLOW_COLOR := Color("33ff00")


## 给物品命中控件及其实际图像绑定荣耀版绿色发光。
## [param hit_target] 接收鼠标进入/离开的控件。
## [param visual] 应用发光材质的物品图像。
## 返回该物品独占的材质实例，供运行时测试或特殊表现组合使用。
static func bind(hit_target: Control, visual: CanvasItem) -> ShaderMaterial:
	assert(hit_target != null and visual != null)
	var material := ShaderMaterial.new()
	material.shader = HOVER_SHADER
	material.set_shader_parameter("glow_color", GLOW_COLOR)
	material.set_shader_parameter("hover_amount", 0.0)
	visual.material = material
	hit_target.mouse_entered.connect(func() -> void: set_hovered(material, true))
	hit_target.mouse_exited.connect(func() -> void: set_hovered(material, false))
	return material


## 切换单件物品的悬停参数，不改写拖拽/锁定使用的 modulate。
## [param material] bind 返回的物品独占材质。
## [param hovered] 是否处于鼠标悬停状态。
static func set_hovered(material: ShaderMaterial, hovered: bool) -> void:
	if material != null:
		material.set_shader_parameter("hover_amount", 1.0 if hovered else 0.0)
