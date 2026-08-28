class_name ShopNpcModel
extends NpcBase


## 查询商店 NPC 默认提供的买卖动作。
## 返回买入和卖出动作数组。
func default_actions() -> Array[Dictionary]:
	return [
		{"id": "buy", "label": "买东西"},
		{"id": "sell", "label": "卖东西"},
	]


## 将商店动作路由到后续商品用例边界。
## [param action_id] buy 或 sell。
## 返回当前阶段的业务路由消息。
func handle_action(action_id: String) -> String:
	return "商店业务“%s”已路由到 %s，商品系统待接入" % [action_id, display_name]
