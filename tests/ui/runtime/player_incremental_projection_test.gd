extends SceneTree

var failures: Array[String] = []
var checks := 0


## 等待节点树后检查原子投影和同帧通知。
func _initialize() -> void:
	call_deferred("_run")


## 验证金币、经验、单个物品更新不会重建不相关对象，非法快照不会部分生效。
func _run() -> void:
	var fixture := PlayerPanelServiceFixture.new()
	_check(fixture.initialize().is_ok, "fixture")
	var first: Dictionary = fixture.execute({"type": "query"}).value
	var session := PlayerPanelSession.new(Callable(), fixture._service._catalog)
	var notifications := [0]
	session.player_changed.connect(func(_player: Player) -> void: notifications[0] += 1)
	session.apply_bundle(first)
	var player := session.current_player
	var old_vehicle := player.vehicle
	var old_inventory := player.inventory
	var old_item := player.inventory.items()[0]
	var next := first.duplicate(true)
	next.transaction_revision += 1
	next.inventory.currency += 100
	session.apply_bundle(next)
	_check(player.vehicle == old_vehicle, "currency preserves vehicle identity")
	_check(player.inventory != old_inventory and player.inventory.items()[0] == old_item, "currency preserves item identity")
	next = next.duplicate(true)
	next.character.skills[0].experience += 1
	session.apply_bundle(next)
	_check(player.vehicle == old_vehicle, "experience without level change preserves loadout")
	var invalid := next.duplicate(true)
	invalid.character.display_name = "must not apply"
	invalid.inventory.items[0].definition_id = "missing.definition"
	_check(not player.apply_bundle(invalid), "invalid item rejects entire candidate")
	_check(player.display_name == first.character.display_name and player.inventory.currency == first.inventory.currency + 100, "failed decode leaves earlier fields unchanged")
	_check(notifications[0] == 0, "same-frame notifications are deferred")
	await process_frame
	await process_frame
	_check(notifications[0] == 1, "three updates emit one final notification")
	_check(player.last_change.inventory_changed and player.last_change.skills_changed, "coalesced flags retain all changes")
	print("PLAYER_INCREMENTAL_PROJECTION checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 记录验证失败，保留全部诊断。
## [param condition] 预期为真。 [param message] 失败原因。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
