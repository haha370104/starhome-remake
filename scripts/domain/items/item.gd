class_name GameItem
extends RefCounted

var instance_id: String
var definition_id: String
var display_name: String
var description: String
var quantity: int
var max_stack: int
var locked: bool
var bound: bool
var container_id: String
var position_px: Vector2i
var footprint_px: Vector2i
var icon_path: String
var presentation: Dictionary
var _definition: Dictionary


## 初始化通用物品实例和值对象属性。
## [param definition] 配置表中的物品定义。
## [param state] 存档中的实例状态。
## 设计：具体物品只按业务类型派生；名称不同的同类物品均由 definition 配置成实例。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	_definition = definition.duplicate(true)
	definition_id = String(definition.get("id", ""))
	display_name = String(definition.get("display_name", definition_id))
	description = String(definition.get("description", ""))
	instance_id = String(state.get("instance_id", ""))
	quantity = maxi(1, int(state.get("quantity", 1)))
	max_stack = maxi(1, int(definition.get("max_stack", 1)))
	locked = bool(state.get("locked", false))
	bound = bool(state.get("bound", false))
	container_id = String(state.get("container_id", "main"))
	position_px = _vector2i(state.get("position_px", [0, 0]), Vector2i.ZERO)
	footprint_px = _vector2i(state.get("footprint_px", [30, 30]), Vector2i(30, 30))
	var item_presentation: Variant = definition.get("presentation", {})
	presentation = (item_presentation as Dictionary).duplicate(true) \
		if item_presentation is Dictionary else {}
	var inventory_presentation := presentation_for("inventory")
	icon_path = String(inventory_presentation.get(
		"icon", presentation.get("icon", presentation_for("world").get("texture", ""))
	))


## 判断两个堆叠能否合并，绑定状态不同或被锁定时禁止合并。
## [param other] 同一背包中的另一个物品。
## 返回是否具有相同定义和绑定属性且支持堆叠。
func can_stack_with(other: GameItem) -> bool:
	return other != null and other != self and max_stack > 1 and not locked and not other.locked \
		and definition_id == other.definition_id and bound == other.bound


## 为拆分创建保持具体类型与绑定属性的新实例，不修改原数量。
## [param new_id] 权威端生成的新实例标识。
## [param amount] 拆出的数量。
## 返回同定义、同表现的新物品。
func copy_stack(new_id: String, amount: int) -> GameItem:
	return get_script().new(_definition, {"instance_id": new_id, "quantity": amount,
		"bound": bound, "locked": locked, "container_id": container_id,
		"position_px": [position_px.x, position_px.y], "footprint_px": [footprint_px.x, footprint_px.y]})


## 按使用场景读取当前物品的表现配置。
## [param mode] inventory、world 或 dialog 等业务表现模式。
## 返回该模式的防御性配置副本；兼容旧平铺配置时隔离背包图与对话框图。
## 设计：同一个物品实例持有一份业务定义，各视图只选择表现模式，不再维护独立物品目录。
func presentation_for(mode: String) -> Dictionary:
	var mode_value: Variant = presentation.get(mode, {})
	if mode_value is Dictionary and not (mode_value as Dictionary).is_empty():
		return (mode_value as Dictionary).duplicate(true)
	if presentation.has("inventory") or presentation.has("dialog") or presentation.has("world"):
		return {}
	var legacy_mode := presentation.duplicate(true)
	if mode == "dialog":
		# 平铺配置的 icon/native_size 属于背包，不能遮蔽独立的 dialog_texture。
		legacy_mode.erase("icon")
		legacy_mode.erase("native_size")
	else:
		legacy_mode.erase("dialog_texture")
	return legacy_mode


## 查询指定表现模式在原客户端中的原生像素尺寸。
## [param mode] inventory、world 或其他业务表现模式。
## 返回表现目录声明的宽高；缺少证据时回退到物品布局占位尺寸。
## 设计：原生绘制尺寸与背包碰撞占位是两个概念，调用方不得用 footprint 缩放贴图。
func visual_size_for(mode: String) -> Vector2i:
	return _vector2i(presentation_for(mode).get("native_size", []), footprint_px)


## 导出背包布局规则需要的最小字典。
## 返回可交给 InventoryLayout 校验器的布局记录。
func to_layout_dictionary() -> Dictionary:
	return {
		"instance_id": instance_id,
		"container_id": container_id,
		"position_px": [position_px.x, position_px.y],
		"footprint_px": [footprint_px.x, footprint_px.y],
		"locked": locked,
	}


## 将布局结果应用回当前物品实例。
## [param layout] 已通过共享布局规则校验的记录。
func apply_layout(layout: Dictionary) -> void:
	container_id = String(layout.get("container_id", container_id))
	position_px = _vector2i(layout.get("position_px", []), position_px)
	footprint_px = _vector2i(layout.get("footprint_px", []), footprint_px)


## 构建客户端背包与提示框共用的安全 DTO。
## 返回不暴露源素材目录的物品视图。
func to_view_dictionary() -> Dictionary:
	return {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"display_name": display_name,
		"description": description,
		"amount": quantity,
		"container_id": container_id,
		"position_px": [position_px.x, position_px.y],
		"footprint_px": [footprint_px.x, footprint_px.y],
		"locked": locked,
		"bound": bound,
		"icon": icon_path,
		"equipment_location": -1,
		"character_slot": "",
	}


## 将二元素数组转换为整数向量。
## [param value] 外部配置或存档值。
## [param fallback] 无效值时采用的默认值。
## 返回解析后的 Vector2i。
static func _vector2i(value: Variant, fallback: Vector2i) -> Vector2i:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback
