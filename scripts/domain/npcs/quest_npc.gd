class_name QuestNpcModel
extends NpcBase


## 查询任务 NPC 默认提供的任务入口。
## 返回查看任务动作数组。
func default_actions() -> Array[Dictionary]:
	return [{"id": "quests", "label": "查看任务"}]


## 将任务动作路由到后续任务用例边界。
## [param action_id] 任务动作标识。
## 返回当前阶段的业务路由消息。
func handle_action(action_id: String) -> String:
	return "任务业务“%s”已路由到 %s，任务系统待接入" % [action_id, display_name]
