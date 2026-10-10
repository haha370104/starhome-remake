class_name WorldSlotMachine
extends Node2D

const MACHINE_TEXTURE := preload("res://assets/world/entertainment/slot_machine/machine.png")
const VISIBLE_REGION := Rect2(52, 30, 144, 142)

var machine_id := ""
var interaction_radius := 90.0
var _sprite: Sprite2D


## 用荣耀版机器图创建可见的大厅交互物。
## [param id] 与权威机器目录一致的标识。[param at] 世界坐标。
func configure(id: String, at: Vector2) -> void:
	machine_id = id
	position = at
	_sprite = Sprite2D.new()
	_sprite.texture = MACHINE_TEXTURE
	_sprite.centered = false
	_sprite.position = Vector2(-118, -155)
	add_child(_sprite)


## 按机器图的实际可见区域命中鼠标。
## [param world_position] 地图坐标。
## 返回是否点中了机器。
func hit_test(world_position: Vector2) -> bool:
	return Rect2(global_position + _sprite.position + VISIBLE_REGION.position,
		VISIBLE_REGION.size).has_point(world_position)


## 构造与其他地图交互物共用的菜单数据。
## 返回开始游戏的操作入口。
func get_interaction_data() -> Dictionary:
	return {"title": "老虎机", "body": "", "actions": [{"id": "play_slot_machine", "label": "开始游戏"}]}


## 显示当前点选状态，不改变游戏机结算状态。
## [param active] 是否选中。
func set_interaction_active(active: bool) -> void:
	_sprite.modulate = Color("e4fbff") if active else Color.WHITE


## 为其他操作返回明确反馈。
## [param _action_id] 未识别的交互动作。
## 返回玩家提示。
func handle_action(_action_id: String) -> String:
	return "请选择开始游戏"
