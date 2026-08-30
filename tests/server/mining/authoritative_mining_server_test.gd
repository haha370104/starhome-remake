extends SceneTree

const ConfigScript := preload("res://scripts/server/server_config.gd")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const UseAbilityIntentScript := preload("res://scripts/network/contracts/use_ability_intent.gd")

var failures: Array[String] = []
var assertions := 0
var _state_path := "res://tests/.tmp_mining_server_state_%d.json" % Time.get_ticks_usec()


## 执行本测试脚本的全部验证并汇总结果。
func _initialize() -> void:
	_test_authoritative_collection_transaction()
	_remove_state_file()
	if failures.is_empty():
		print("AUTHORITATIVE_MINING_SERVER_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 验证 `test_authoritative_collection_transaction` 对应的业务约束。
func _test_authoritative_collection_transaction() -> void:
	var config := ConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = true
	config.player_state_store_path = _state_path
	config.map_config_path = "res://data/maps/d04_field_zone.json"
	config.default_spawn = Vector2(1200, 1200)
	var server = ServerScript.new()
	var initialized: Dictionary = server.initialize(config)
	_expect(initialized.ok, "mining server should initialize: %s" % initialized)
	if not initialized.ok:
		return
	var opened: Dictionary = server.open_session(41, {
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"content_version": Protocol.PUBLIC_CONTENT_VERSION,
	}, 1000)
	_expect(opened.ok, "mining actor should open a persisted session")
	if not opened.ok:
		return
	var entity_id := String(opened.value.session.entity_id)
	var source = server.map_instance.mining_module.sources.values()[0]
	var entity = server.map_instance.entities[entity_id]
	entity.position = source.position + Vector2(40, 0)
	entity.target_position = entity.position
	server.map_instance.combat_module.update_actor_position(entity_id, entity.position)
	var intent := UseAbilityIntentScript.new(
		server.map_instance.instance_id,
		"mining.collect",
		source.position,
		1,
	)
	var started: Dictionary = server.handle_peer_use_ability(41, intent.to_dictionary())
	_expect(started.ok and StringName(started.value.event_type) == &"mining_started", "server should accept an eligible mine selection")
	server.advance_simulation(2.95)
	var before = server.autosave_service.state_for(entity_id)
	_expect(_inventory_quantity(before, "iron_ore") == 0, "inventory must not change before the third second")
	server.advance_simulation(0.05)
	var after = server.autosave_service.state_for(entity_id)
	_expect(_inventory_quantity(after, "iron_ore") == 1, "third-second settlement should add one iron ore")
	_expect(source.remaining == 49, "settled collection should reduce the selected source from fifty to forty-nine")
	var mining_state: Dictionary = after.character_skills.get("mining", {})
	_expect(
		int(mining_state.get("current_exp", -1)) == 0
			and float(mining_state.get("fractional_exp", 0.0)) > 0.0,
		"one iron should grant one twenty-fifth of the current mining-level threshold",
	)
	var combat_snapshot: Dictionary = server.snapshot_for_peer(41).get("combat", {})
	_expect((combat_snapshot.get("mine_sources", []) as Array).size() == 20, "peer snapshot should publish all twenty authoritative mine sources")
	server.free()


## 执行 `inventory_quantity` 对应的模块操作。
## [param state] 调用方传入的 `state` 参数。
## [param definition_id] 调用方传入的 `definition_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _inventory_quantity(state, definition_id: String) -> int:
	if state == null:
		return 0
	var quantity := 0
	for stack in state.inventory_stacks:
		if stack.item_definition_id == definition_id:
			quantity += stack.quantity
	return quantity


## 执行 `remove_state_file` 对应的模块操作。
func _remove_state_file() -> void:
	var absolute := ProjectSettings.globalize_path(_state_path)
	if FileAccess.file_exists(_state_path):
		DirAccess.remove_absolute(absolute)


## 记录一项测试断言及其失败信息。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
