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


## 初始化通用物品实例和值对象属性。
## [param definition] 配置表中的物品定义。
## [param state] 存档中的实例状态。
## 设计：具体物品只按业务类型派生；名称不同的同类物品均由 definition 配置成实例。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
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
	icon_path = String(presentation.get("icon", ""))


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
