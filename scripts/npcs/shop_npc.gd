class_name ShopNpc
extends "res://scripts/npcs/npc_base.gd"


func default_actions() -> Array:
	return [
		{"id": "buy", "label": "买东西"},
		{"id": "sell", "label": "卖东西"},
	]


func handle_action(action_id: String) -> String:
	return "商店业务“%s”已路由到 %s，商品系统待接入" % [
		action_id,
		String(npc_definition.get("name", npc_id)),
	]
