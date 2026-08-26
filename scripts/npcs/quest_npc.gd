class_name QuestNpc
extends "res://scripts/npcs/npc_base.gd"


func default_actions() -> Array:
	return [{"id": "quests", "label": "查看任务"}]


func handle_action(action_id: String) -> String:
	return "任务业务“%s”已路由到 %s，任务系统待接入" % [
		action_id,
		String(npc_definition.get("name", npc_id)),
	]
