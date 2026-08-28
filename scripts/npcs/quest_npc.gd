class_name QuestNpc
extends "res://scripts/npcs/npc_base.gd"


## 执行 `default_actions` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func default_actions() -> Array:
	return [{"id": "quests", "label": "查看任务"}]


## 校验并处理 `handle_action` 对应的模块状态。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func handle_action(action_id: String) -> String:
	return "任务业务“%s”已路由到 %s，任务系统待接入" % [
		action_id,
		String(npc_definition.get("name", npc_id)),
	]
