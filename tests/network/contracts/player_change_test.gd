extends SceneTree

var _checks := 0
var _failures := 0


## 验证行增量、连续性恢复、连接隔离以及业务外壳兼容。
func _initialize() -> void:
	var sender := PlayerSyncStream.new()
	var receiver := PlayerSyncStream.new()
	var first := {"transaction_revision": 1, "character": {"character_id": "a", "skills": [{"id": "driving", "level": 1}]},
		"inventory": {"items": [{"instance_id": "i1", "quantity": 2}, {"instance_id": "i2", "quantity": 1}]}, "vehicle": {}, "food_status": {"id": "food"}}
	var full := sender.encode(first)
	_expect(receiver.decode(full.player_change).value == first, "完整初始化")
	var next := first.duplicate(true)
	next.inventory.items = [{"instance_id": "i2", "quantity": 3}]
	next.character.skills[0].level = 2
	next.food_status = {}
	var delta := sender.encode(next)
	_expect(delta.player_change.patch.rows.is_empty(), "行补丁位于组件内")
	_expect(delta.player_change.patch.children.inventory.rows.items.changed.size() == 1, "只传变化的物品行")
	_expect(receiver.decode(delta.player_change).value == next, "删除、改序、技能及空状态一致")
	_expect(not receiver.decode(delta.player_change).is_ok, "重复拒绝")
	sender.encode(first)
	var missing := sender.encode(next)
	_expect(receiver.decode(missing.player_change).error_code == &"player_sync.gap", "断档拒绝")
	sender.require_full()
	_expect(receiver.decode(sender.encode(next).player_change).value == next, "全量修复断档")
	var malformed: Dictionary = sender.encode(first).player_change
	malformed.patch.children.inventory.rows.items.order = ["missing"]
	_expect(not receiver.decode(malformed).is_ok, "缺行补丁原子拒绝")
	sender.require_full()
	_expect(receiver.decode(sender.encode(first).player_change).value == first, "格式错误后可恢复")
	sender.reset()
	_expect(receiver.decode(sender.encode(next).player_change).value == next, "重连新代号从一开始")
	var publisher := PlayerSyncPublisher.new()
	var message := {"type": "loot_pickup", "result": {"ok": true, "value": {"loot_id": "drop", "panel_bundle": first}}}
	_expect(publisher.encode(1, message) == message, "旧客户端保留完整协议")
	publisher.connect_peer(1, 1)
	var wire := publisher.encode(1, message)
	_expect(wire.result.value.panel_bundle.has("player_change"), "嵌套投影编码")
	var peer := PlayerSyncStream.new()
	var decoded := PlayerSyncMessages.transform(wire, func(value: Dictionary) -> DomainResult: return peer.decode(value.player_change))
	_expect(decoded.value == message, "拾取结果外壳保留")
	_expect(publisher.encode(2, message) == message, "另一连接不受影响")
	publisher.require_full(1)
	_expect(publisher.encode(1, message).result.value.panel_bundle.player_change.has("full"), "查询可强制全量")
	publisher.disconnect_peer(1)
	_expect(publisher.encode(1, message) == message, "断开释放基线")
	print("PLAYER_CHANGE checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures else 0)


## 累计断言并保留全部失败信息。
## [param valid] 条件。[param message] 失败说明。
func _expect(valid: bool, message: String) -> void:
	_checks += 1
	if not valid:
		_failures += 1
		push_error(message)

