class_name AuthoritativeSlotMachineService
extends RefCounted

var _catalog: ItemCatalog
var _random := RandomNumberGenerator.new()


## 使用现有物品目录准备金币事务，随机数只由服务端生成。
## [param catalog] 在线玩家使用的物品目录。
func _init(catalog: ItemCatalog) -> void:
	_catalog = catalog
	_random.randomize()


## 校验会话地图、机器及实际人物距离，再查询或结算一次下注。
## [param player] 在线玩家。[param map_id] 会话所在地图。
## [param position] 模拟器中的权威人物坐标。[param command] 客户端意图。
## 返回隔离候选和老虎机结果；拒绝时不更改在线状态。
func execute(player: Player, map_id: String, position: Vector2, command: Dictionary) -> DomainResult:
	var machine_id := String(command.get("machine_id", ""))
	if not SlotMachineRules.supports_map(map_id) or not SlotMachineRules.MACHINES.has(machine_id):
		return DomainResult.failure(&"slot_machine.unavailable", "当前地点没有这台游戏机")
	if position.distance_to(SlotMachineRules.MACHINES[machine_id]) > 190.0:
		return DomainResult.failure(&"slot_machine.too_far", "请走近游戏机")
	var kind := String(command.get("type", ""))
	if kind == "query_slot_machine":
		return DomainResult.ok({"changed": false, "slot_machine": {
			"machine_id": machine_id, "balance": player.inventory.currency,
			"max_bet": SlotMachineRules.MAX_BET,
		}})
	if kind != "spin_slot_machine":
		return DomainResult.failure(&"slot_machine.invalid_command", "不支持的游戏机操作")
	var bet_value: Variant = command.get("bet")
	if not bet_value is int or bet_value < SlotMachineRules.MIN_BET or bet_value > SlotMachineRules.MAX_BET:
		return DomainResult.failure(&"slot_machine.invalid_bet", "下注额须为 1 至 100 金币")
	var bet: int = bet_value
	if player.inventory.currency < bet:
		return DomainResult.failure(&"inventory.insufficient_currency", "金币余额不足")
	var prepared := PlayerTransaction.prepare(player, ["inventory"], _catalog)
	if not prepared.is_ok:
		return prepared
	var candidate: Player = prepared.value
	var spent := candidate.inventory.spend_currency(bet)
	if not spent.is_ok:
		return spent
	var symbols := SlotMachineRules.draw(_random)
	var result := SlotMachineRules.settle(symbols, bet)
	if result.payout > 9223372036854775807 - candidate.inventory.currency:
		return DomainResult.failure(&"slot_machine.currency_overflow", "余额已达上限")
	candidate.inventory.currency += result.payout
	result.merge({"machine_id": machine_id, "symbols": symbols,
		"bet": bet, "balance": candidate.inventory.currency}, true)
	return DomainResult.ok({"candidate": candidate, "changed": true, "slot_machine": result})
