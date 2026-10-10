class_name PlayerPanelCoordinator
extends RefCounted

var _session_for_peer: Callable
var _player_for: Callable
var _persistence_available: Callable
var _map_for_instance: Callable
var _exit_execute: Callable
var _capture_player: Callable
var _commit_player: Callable
var _update_runtime: Callable
var _scene_players: Callable
var _build_loadout: Callable
var _apply_food: Callable
var _send_reliable: Callable
var _wire_result: Callable
var _queue_player_change: Callable
var _flush_player_changes: Callable
var _player_panel_service: AuthoritativePlayerPanelService
var _commerce_service: AuthoritativeCommerceService
var _manufacturing_service: AuthoritativeManufacturingService
var _warehouse_service: PersonalWarehouseService
var _slot_machine_service: AuthoritativeSlotMachineService
var _garden_service: AuthoritativeGardenService
var _configured := false
const SIMPLE_COMMIT_DOMAINS := {
	"move_inventory_item": ["inventory"], "arrange_inventory": ["inventory"],
	"split_inventory_item": ["inventory"], "merge_inventory_item": ["inventory"],
	"use_inventory_item": ["character", "food", "inventory"],
	"equip_vehicle_item": ["inventory", "vehicle"], "unequip_vehicle_item": ["inventory", "vehicle"],
	"equip_character_item": ["character", "inventory"], "unequip_character_item": ["character", "inventory"],
	"capture_vehicle_preset": ["presets"], "apply_vehicle_preset": ["inventory", "presets", "vehicle"],
}
const EQUIPMENT_COMMAND_GROUPS := [
	ClothingEnhancementService.COMMANDS, VehicleSocketService.COMMANDS,
	CrystalSourceService.COMMANDS, AustinGlensService.COMMANDS, SamaService.COMMANDS,
	CentralService.COMMANDS, EquipmentProcessingService.COMMANDS, EquipmentMaintenanceService.COMMANDS,
]


## 配置面板、生产和设施用例所需的服务与服务器副作用端口。
## 玩家聚合、生产时钟、地图实体和可靠发送仍由注入端口的调用方拥有。
func configure(
	session_for_peer: Callable,
	player_for: Callable,
	persistence_available: Callable,
	map_for_instance: Callable,
	exit_execute: Callable,
	capture_player: Callable,
	commit_player: Callable,
	update_runtime: Callable,
	scene_players: Callable,
	build_loadout: Callable,
	apply_food: Callable,
	send_reliable: Callable,
	wire_result: Callable,
	queue_player_change: Callable,
	flush_player_changes: Callable,
	player_panel_service: AuthoritativePlayerPanelService,
	commerce_service: AuthoritativeCommerceService,
	manufacturing_service: AuthoritativeManufacturingService,
	warehouse_service: PersonalWarehouseService,
	slot_machine_service: AuthoritativeSlotMachineService,
	garden_service: AuthoritativeGardenService,
) -> DomainResult:
	var ports := [
		session_for_peer,
		player_for,
		persistence_available,
		map_for_instance,
		exit_execute,
		capture_player,
		commit_player,
		update_runtime,
		scene_players,
		build_loadout,
		apply_food,
		send_reliable,
		wire_result,
		queue_player_change,
		flush_player_changes,
	]
	for port: Callable in ports:
		if not port.is_valid():
			return DomainResult.failure(&"panel_coordinator.invalid_port", "all panel coordinator ports are required")
	_session_for_peer = session_for_peer
	_player_for = player_for
	_persistence_available = persistence_available
	_map_for_instance = map_for_instance
	_exit_execute = exit_execute
	_capture_player = capture_player
	_commit_player = commit_player
	_update_runtime = update_runtime
	_scene_players = scene_players
	_build_loadout = build_loadout
	_apply_food = apply_food
	_send_reliable = send_reliable
	_wire_result = wire_result
	_queue_player_change = queue_player_change
	_flush_player_changes = flush_player_changes
	_player_panel_service = player_panel_service
	_commerce_service = commerce_service
	_manufacturing_service = manufacturing_service
	_warehouse_service = warehouse_service
	_slot_machine_service = slot_machine_service
	_garden_service = garden_service
	_configured = true
	return DomainResult.ok(self)


## 执行绑定到 peer 的人物、背包、战车、生产和设施面板命令。
## 返回与原服务器入口兼容的权威结果；不持有第二份玩家状态。
func execute(peer_id: int, command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"panel_coordinator.unavailable", "panel coordinator is not configured")
	var session: ServerSession = _session_for_peer.call(peer_id)
	if command.get("type") == "prepare_exit":
		var exit_result: DomainResult = _exit_execute.call(peer_id, session, command)
		return _success(exit_result.value) if exit_result.is_ok else _failure(
			exit_result.error_code, exit_result.error_message
		)
	return execute_session(session, command)


func execute_session(session: ServerSession, command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"panel_coordinator.unavailable", "panel coordinator is not configured")
	if session == null:
		return _failure(&"panels.session_missing", "peer has no active authoritative session")
	if not bool(_persistence_available.call()) or _player_panel_service == null \
			or _commerce_service == null or _manufacturing_service == null:
		return _failure(&"panels.persistence_required", "player panels require authoritative persistence")
	var current: Player = _player_for.call(session.entity_id)
	if current == null:
		return _failure(&"panels.state_missing", "authoritative player state is not registered")
	var command_type := String(command.get("type", ""))
	if command_type == "drop_inventory_item":
		return _drop_inventory_item(session, current, command)
	if command_type == "query_vehicle_presets":
		return _success({"vehicle_presets": current.vehicle_presets.to_dictionary(),
			"preset_server_time": int(Time.get_unix_time_from_system()),
			"sync_id": session.sync_id, "transaction_revision": current.revision})
	if command_type == "close_manufacturing":
		session.manufacturing_station = ""
		return _success({})
	if command_type == "query_daily_activities":
		var daily: DailyActivityService = _commerce_service.daily
		var prepared := current.daily_activities.prepare_day(daily.current_day(), daily.catalog, current.level)
		current.daily_activities.commit(prepared)
		if prepared.changed():
			var runtime_result: DomainResult = _update_runtime.call(current)
			if not runtime_result.is_ok:
				return _failure(runtime_result.error_code, runtime_result.error_message)
			var daily_change := PlayerChange.new()
			daily_change.revision = current.revision
			daily_change.daily = daily.snapshot(current)
			_queue_player_change.call(current.entity_id, daily_change)
			_flush_player_changes.call()
		return _success({"daily_activities": daily.snapshot(current),
			"inventory": {"revision": current.inventory.revision},
			"sync_id": session.sync_id, "transaction_revision": current.revision})
	if command_type == "query_scene_players":
		return _success({"scene_players": _scene_players.call(session.map_instance_id)})
	if command_type == "query_public_player_profile":
		var target_id := String(command.get("target_entity_id", ""))
		if String(command.get("view", "")) not in ["character", "vehicle"]:
			return _failure(&"profile.invalid_view", "未知的人物查看类型")
		var visible := false
		for row: Dictionary in _scene_players.call(session.map_instance_id).get("players", []):
			if String(row.get("entity_id", "")) == target_id:
				visible = true
				break
		if not visible:
			return _failure(&"profile.player_not_here", "该玩家不在当前场景")
		current = _player_for.call(target_id)
		if current == null:
			return _failure(&"profile.player_not_here", "该玩家不在当前场景")
	if command_type in ["query_slot_machine", "spin_slot_machine"]:
		return _execute_slot_machine(session, current, command)
	if command_type in ["query_garden", "harvest_garden"]:
		return _execute_garden(session, current, command)
	var is_warehouse := command_type in PersonalWarehouseService.COMMANDS
	if is_warehouse and _warehouse_service == null:
		return _failure(&"warehouse.unavailable", "个人仓库尚未初始化")
	var is_commerce: bool = AuthoritativeCommerceService.handles(command_type)
	var is_manufacturing: bool = _manufacturing_service.handles(command_type)
	var current_map: AuthoritativeMapInstance = _map_for_instance.call(session.map_instance_id)
	var captured: DomainResult = _capture_player.call(current)
	if not captured.is_ok:
		return _failure(captured.error_code, captured.error_message)
	current = captured.value
	if command_type == "query_public_player_profile":
		return _success({"public_player_profile": {"target_entity_id": current.entity_id,
			"display_name": current.display_name, "view": String(command.view),
			"snapshot": _player_panel_service.build_public_view(current, String(command.view))}})
	var trusted_command := command.duplicate(true)
	trusted_command["_authoritative_vehicle_combat_active"] = current_map != null \
		and current_map.is_vehicle_combat_active()
	var executed: DomainResult
	if is_commerce:
		executed = _commerce_service.execute(current, trusted_command)
	elif is_manufacturing:
		executed = _manufacturing_service.execute(current, trusted_command)
	elif is_warehouse:
		executed = _warehouse_service.execute(current, trusted_command)
	else:
		executed = _player_panel_service.execute(current, trusted_command)
	if not executed.is_ok:
		return _failure(executed.error_code, executed.error_message)
	var value: Dictionary = executed.value
	if is_manufacturing:
		session.manufacturing_station = String(value.get("operation", {}).get("station_id", ""))
	if not bool(value.get("changed", false)):
		return _success(value["panel_bundle"])
	var change: PlayerChange = value.get("change")
	if is_commerce and command_type in ["buy_from_weapon_merchant", "sell_to_weapon_merchant"]:
		change = _player_panel_service.changes(current, value["candidate"])
	if is_manufacturing:
		change = _player_panel_service.changes(current, value.candidate)
	var refresh_combat := change == null or change.attributes_changed
	var prepared_loadout: Dictionary = {}
	if refresh_combat and command_type != "use_inventory_item" \
			and current_map != null and current_map.is_vehicle_combat_active():
		var built_loadout: DomainResult = _build_loadout.call(current_map, value["candidate"])
		if not built_loadout.is_ok:
			return _failure(built_loadout.error_code, built_loadout.error_message)
		prepared_loadout = built_loadout.value
	var previous_loadout_revision := current.vehicle.loadout.revision
	var commit_domains := _commit_domains_for_command(
		command_type, is_commerce, is_manufacturing, is_warehouse
	)
	var committed: DomainResult = _commit_player.call(
		session.entity_id, value["candidate"], is_manufacturing, {}, commit_domains
	)
	if not committed.is_ok:
		return _failure(committed.error_code, committed.error_message)
	if current_map != null and current_map.mining_module != null \
			and previous_loadout_revision != committed.value.vehicle.loadout.revision:
		current_map.mining_module.interrupt(session.entity_id, &"equipment_changed")
	var special_location := int(command.get("location", -1))
	if command_type == "equip_vehicle_item":
		for slot: VehicleEquipment in committed.value.vehicle.loadout.items():
			if slot.instance_id == String(command.get("instance_id", "")):
				special_location = slot.equipment_location
	var special_equipment_changed := command_type in ["equip_vehicle_item", "unequip_vehicle_item"] \
		and not EquipmentSlotRegistry.special_series(special_location).is_empty()
	if command_type in AuthoritativeCommerceService.TASK_COMMANDS and refresh_combat \
			and current_map != null and current_map.is_vehicle_combat_active():
		var refreshed_task_loadout := current_map.refresh_achievement_loadout(
			session.entity_id, prepared_loadout
		)
		if not refreshed_task_loadout.is_ok:
			return _failure(refreshed_task_loadout.error_code, refreshed_task_loadout.error_message)
	elif command_type == "use_inventory_item":
		_apply_food.call(session.entity_id, committed.value, change.attributes_changed)
	elif (command_type in ClothingEnhancementService.COMMANDS \
			or command_type in VehicleSocketService.COMMANDS \
			or command_type in CrystalSourceService.COMMANDS \
			or command_type in AustinGlensService.COMMANDS \
			or command_type in SamaService.COMMANDS \
			or command_type in CentralService.COMMANDS \
			or special_equipment_changed \
			or command_type in EquipmentProcessingService.COMMANDS \
			or command_type in EquipmentMaintenanceService.COMMANDS \
			or command_type in ["equip_character_item", "unequip_character_item", "apply_vehicle_preset"]) \
			and current_map != null and current_map.is_vehicle_combat_active():
		var enhanced_loadout := current_map.refresh_achievement_loadout(
			session.entity_id, prepared_loadout
		)
		if not enhanced_loadout.is_ok:
			return _failure(enhanced_loadout.error_code, enhanced_loadout.error_message)
		if current_map.mining_module != null:
			current_map.mining_module.interrupt(session.entity_id, &"clothing_changed")
	elif refresh_combat and command_type not in ["split_inventory_item", "merge_inventory_item", "capture_vehicle_preset"] \
			and current_map != null and current_map.is_vehicle_combat_active():
		var refreshed_loadout := current_map.set_vehicle_combat_loadout(
			session.entity_id, prepared_loadout
		)
		if not refreshed_loadout.ok:
			return refreshed_loadout
	if is_commerce:
		var operation: Dictionary = value.get("operation", {})
		if operation.get("skill_level_up") is Dictionary and session.has_active_peer():
			_send_reliable.call(session.peer_id, {"type": "skill_level_up",
				"result": _wire_result.call(_success(operation["skill_level_up"]))})
		if command_type in AuthoritativeCommerceService.TASK_COMMANDS:
			_queue_player_change.call(session.entity_id, change)
			return _success(_commerce_service.build_task_bundle(committed.value, operation))
		if command_type in ["buy_from_weapon_merchant", "sell_to_weapon_merchant"]:
			_queue_player_change.call(session.entity_id, change)
			return _success({"player_change": {}})
		return _success(_commerce_service.build_bundle(committed.value, value.get("operation", {})))
	if is_manufacturing:
		_queue_player_change.call(session.entity_id, change)
		var bundle: Dictionary = _manufacturing_service.build_bundle(
			committed.value, value.get("operation", {})
		)
		bundle["player_change"] = {}
		return _success(bundle)
	if is_warehouse:
		var warehouse_bundle: Dictionary = value["panel_bundle"]
		warehouse_bundle["transaction_revision"] = committed.value.revision
		_queue_player_change.call(session.entity_id, change)
		warehouse_bundle["player_change"] = {}
		return _success(warehouse_bundle)
	_queue_player_change.call(session.entity_id, change)
	return _success({"player_change": {}, "operation": value.get("operation")})


func _drop_inventory_item(session: ServerSession, current: Player, command: Dictionary) -> Dictionary:
	var map: AuthoritativeMapInstance = _map_for_instance.call(session.map_instance_id)
	var point: Variant = command.get("position")
	if map == null or map.combat_module == null or not map.entities.has(session.entity_id) \
		or command.get("map_instance_id") != session.map_instance_id:
		return _failure(&"loot.map_mismatch", "当前地图已变更，请重试")
	if not point is Array or point.size() != 2 \
		or not (point[0] is int or point[0] is float) or not (point[1] is int or point[1] is float):
		return _failure(&"loot.invalid_position", "丢弃位置无效")
	var position := Vector2(point[0], point[1])
	if not position.is_finite() or map.entities[session.entity_id].position.distance_to(position) > Inventory.WORLD_DROP_RADIUS \
		or not map.navigation.is_walkable(position):
		return _failure(&"loot.out_of_range", "只能放在自己附近可行走的地面上")
	var revision: Variant = command.get("inventory_revision")
	if not (revision is int or revision is float) or revision != current.inventory.revision:
		return _failure(&"inventory.revision_conflict", "背包状态已更新，请重试")
	var identity: Variant = command.get("instance_id")
	var item: GameItem = current.inventory.find(identity) if identity is String else null
	if item == null or item.locked or item.bound:
		return _failure(&"inventory.item_locked", "物品不存在，或已锁定、绑定")
	var mapped := PlayerTransaction.prepare(current, ["inventory"], _player_panel_service.catalog, [], [item.instance_id])
	if not mapped.is_ok: return _failure(mapped.error_code, mapped.error_message)
	var candidate: Player = mapped.value
	item = candidate.inventory.remove_for_transfer(item.instance_id).value
	candidate.inventory.commit_transfer()
	var recorded := InventoryStackRecord.from_item(item, 0)
	if not recorded.is_ok: return _failure(recorded.error_code, recorded.error_message)
	var loot_id := "dropped." + Crypto.new().generate_random_bytes(16).hex_encode()
	var transfer := {"map_id": String(map.definition.map_id), "loot_id": loot_id,
		"item": {"position": [position.x, position.y], "item": recorded.value.to_dictionary()}}
	var change := _player_panel_service.changes(current, candidate)
	var committed: DomainResult = _commit_player.call(
		session.entity_id, candidate, false, transfer, ["inventory"] as Array[String]
	)
	if not committed.is_ok: return _failure(committed.error_code, committed.error_message)
	map.combat_module.drop_item(loot_id, session.map_instance_id, item, position)
	_queue_player_change.call(session.entity_id, change)
	return _success({"player_change": {}})


func _execute_slot_machine(session: ServerSession, current: Player, command: Dictionary) -> Dictionary:
	var map: AuthoritativeMapInstance = _map_for_instance.call(session.map_instance_id)
	var entity: AuthoritativeEntity = map.entities.get(session.entity_id) if map != null else null
	if entity == null:
		return _failure(&"slot_machine.player_missing", "当前地图中找不到人物")
	var slot_result: DomainResult = _slot_machine_service.execute(
		current, String(map.definition.map_id), entity.position, command
	)
	if not slot_result.is_ok:
		return _failure(slot_result.error_code, slot_result.error_message)
	var slot_value: Dictionary = slot_result.value
	if not slot_value.changed:
		return _success({"slot_machine": slot_value.slot_machine})
	var slot_change := _player_panel_service.changes(current, slot_value.candidate)
	var slot_committed: DomainResult = _commit_player.call(session.entity_id, slot_value.candidate, false)
	if not slot_committed.is_ok:
		return _failure(slot_committed.error_code, slot_committed.error_message)
	_queue_player_change.call(session.entity_id, slot_change)
	return _success({"slot_machine": slot_value.slot_machine, "player_change": {}})


func _execute_garden(session: ServerSession, current: Player, command: Dictionary) -> Dictionary:
	var garden_map: AuthoritativeMapInstance = _map_for_instance.call(session.map_instance_id)
	var garden_actor: AuthoritativeEntity = garden_map.entities.get(session.entity_id) \
		if garden_map != null else null
	if garden_actor == null:
		return _failure(&"garden.player_missing", "当前地图中找不到人物")
	var garden_map_id := String(garden_map.definition.map_id)
	var now := int(Time.get_unix_time_from_system())
	if command.get("type") == "query_garden":
		var state: DomainResult = _garden_service.query(current, garden_map_id, now)
		return _success({"garden": state.value}) if state.is_ok else _failure(
			state.error_code, state.error_message
		)
	var plant_id := String(command.get("plant_id", ""))
	var harvest: DomainResult = _garden_service.prepare_harvest(
		current, garden_map_id, garden_actor.position, plant_id, now
	)
	if not harvest.is_ok:
		return _failure(harvest.error_code, harvest.error_message)
	var prepared: DomainResult = PlayerTransaction.prepare(
		current, ["inventory"], _player_panel_service.catalog
	)
	if not prepared.is_ok:
		return _failure(prepared.error_code, prepared.error_message)
	var candidate: Player = prepared.value
	var granted: DomainResult = _player_panel_service.receive_loot(candidate, harvest.value)
	if not granted.is_ok:
		return _failure(granted.error_code, granted.error_message)
	var garden_committed: DomainResult = _commit_player.call(session.entity_id, candidate, false)
	if not garden_committed.is_ok:
		return _failure(garden_committed.error_code, garden_committed.error_message)
	var remaining := _garden_service.commit_harvest(garden_committed.value, plant_id, now)
	_queue_player_change.call(
		session.entity_id,
		_player_panel_service.pickup_change(garden_committed.value, granted.value),
	)
	return _success({"garden": {"map_id": garden_map_id, "plant_id": plant_id,
		"remaining_seconds": remaining, "item_name": granted.value.display_name}, "player_change": {}})


## 返回面板事务实际写入的持久化领域，避免一次装备或背包操作把大成就账本重新复制。
func _commit_domains_for_command(
	command_type: String,
	is_commerce: bool,
	is_manufacturing: bool,
	is_warehouse: bool,
) -> Array[String]:
	if is_warehouse:
		return ["inventory", "warehouse"] as Array[String]
	if is_manufacturing:
		return ["character", "inventory", "production", "skills"] as Array[String]
	if is_commerce:
		return ["achievements", "character", "daily", "inventory", "quests", "vehicle"] as Array[String]
	var simple: Variant = SIMPLE_COMMIT_DOMAINS.get(command_type)
	if simple != null: return _typed_domains(simple)
	for commands: Array in EQUIPMENT_COMMAND_GROUPS:
		if command_type in commands: return ["character", "central", "inventory", "vehicle"] as Array[String]
	return [] as Array[String]


func _typed_domains(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values: result.append(String(value))
	return result


func _success(value: Variant) -> Dictionary:
	return {"ok": true, "code": &"ok", "value": value}


func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
