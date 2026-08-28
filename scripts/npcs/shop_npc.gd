class_name ShopNpc
extends "res://scripts/npcs/npc_base.gd"

const ShopNpcModelScript := preload("res://scripts/domain/npcs/shop_npc.gd")


## 执行 `default_actions` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func create_npc_model() -> NpcBase:
	return ShopNpcModelScript.new()


## 校验并处理 `handle_action` 对应的模块状态。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func handle_action(action_id: String) -> String:
	return npc_model.handle_action(action_id)
