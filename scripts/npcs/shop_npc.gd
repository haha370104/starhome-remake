class_name ShopNpc
extends "res://scripts/npcs/npc_base.gd"


## Provides the default interaction actions exposed by this NPC type.
## Returns the resulting collection.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func default_actions() -> Array:
	return [
		{"id": "buy", "label": "买东西"},
		{"id": "sell", "label": "卖东西"},
	]


## Processes the requested protocol or gameplay operation.
## [param action_id] Stable identifier of the target value.
## Returns the resolved string value.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func handle_action(action_id: String) -> String:
	return "商店业务“%s”已路由到 %s，商品系统待接入" % [
		action_id,
		String(npc_definition.get("name", npc_id)),
	]
