class_name AiAuthorityAdapter
extends AiWorldPort

var _server: AuthoritativeServer
var _radius: float
var _owned: Dictionary = {}
var _facilities: Dictionary = {}


## 将现有权威服务器适配为窄世界端口；只有此适配器认识服务器具体类型。
## [param server] 已初始化服务器。[param radius] 可见目标半径。
func _init(server: AuthoritativeServer, radius: float) -> void:
	_server = server
	_radius = radius
	var loaded := JsonConfigLoader.load_dictionary("res://data/world/manufacturing_facilities_v1.json")
	if loaded.is_ok: _facilities = loaded.value.get("maps", {})


## 使用独立稳定身份创建角色，保留普通玩家的登录顺序与存档。
## [param key] 配置角色标识。
## 返回本适配器拥有的会话。
func open_actor(key: String) -> DomainResult:
	var opened := _server.open_local_actor("ai_" + key)
	if not opened.ok: return _result(opened)
	var actor := AiPlayerActor.new()
	actor.key = key
	actor.peer_id = int(opened.value.session.peer_id)
	actor.entity_id = String(opened.value.session.entity_id)
	_owned[actor.peer_id] = actor
	return DomainResult.ok(actor)


## 只投影自身资源和附近有限目标，不读取其他玩家私人状态。
## [param actor] 本适配器创建的会话。
## 返回单次有限观察或失效原因。
func observe(actor: AiPlayerActor) -> DomainResult:
	var map := _map(actor)
	if map == null: return DomainResult.failure(&"ai.session_lost", "AI会话已失效")
	var entity: AuthoritativeEntity = map.entities[actor.entity_id]
	var state := _server.autosave_service.state_for(actor.entity_id)
	if state == null: return DomainResult.failure(&"ai.state_missing", "AI角色存档不可用")
	var view := AiPlayerObservation.new()
	view.map_id = String(map.definition.map_id)
	view.map_name = map.definition.display_name
	view.position = entity.position
	view.moving = entity.action == &"walking"
	view.combat_active = map.is_vehicle_combat_active()
	view.health = state.character_health
	view.max_health = state.character_max_health
	var inventory: Array[Dictionary] = []
	for stack: InventoryStackRecord in state.inventory_stacks:
		if inventory.size() >= 80: break
		inventory.append({"instance_id": stack.stack_id, "definition_id": stack.item_definition_id,
			"name": _item_name(stack.item_definition_id), "quantity": stack.quantity})
	var equipment: Array[Dictionary] = []
	for slot: EquipmentSlotRecord in state.equipment_slots: equipment.append(slot.to_dictionary())
	view.own_state = {"inventory": inventory, "equipment": equipment, "currency": state.currency,
		"skills": state.character_skills.duplicate(true), "quests": state.quest_states.duplicate(true),
		"production": state.production.to_dictionary(), "merchants": [], "stations": []}
	for id: String in _server.commerce_service.quests.catalog.providers:
		var merchant: Dictionary = _server.commerce_service.quests.catalog.providers[id]
		if view.map_id in merchant.get("map_ids", []):
			view.own_state.merchants.append({"id": id, "name": merchant.get("display_name", id)})
	for facility: Dictionary in _facilities.get(view.map_id, []):
		view.own_state.stations.append({"id": facility.station_id, "position": facility.position})
	for transition: MapTransition in map.definition.enabled_transitions():
		_add(view, "travel", String(transition.transition_id), transition.label,
			transition.approach_point, 0, true, false)
	if map.combat_module != null and view.combat_active:
		var private_state := map.combat_module.private_snapshot(actor.entity_id)
		view.own_state["combat"] = private_state
		var vehicle: Dictionary = private_state.get("local_vehicle", {})
		view.health = int(vehicle.get("health", 0))
		view.max_health = int(vehicle.get("max_health", 1))
		for monster: MonsterLifecycle in map.combat_module.monsters.values():
			if monster.is_alive(): _add(view, "hunt", monster.monster_id, monster.display_name, monster.position, monster.health)
		for loot: Dictionary in map.combat_module.ground_loot.values():
			# 模块自限：不抢其他玩家战利品，仍经正式拾取事务结算。
			if loot.get("killer_id", "") != actor.entity_id: continue
			_add(view, "pickup", loot.loot_id, _item_name(loot.item_definition_id), Vector2(loot.position[0], loot.position[1]))
	if map.mining_module != null:
		for source: MineSource in map.mining_module.sources.values():
			_add(view, "mine", source.source_id, "%s（采掘%d级）" % [source.display_name, source.required_mining_level], source.position, 0, source.remaining > 0)
	var garden := _server.garden_service.rules
	if view.map_id == garden.map_id:
		for plant: BotanicalGardenCatalog.Plant in garden.plants:
			_add(view, "harvest", plant.id, _item_name(plant.item_id), plant.position, 0,
				state.garden.remaining(plant.id, int(Time.get_unix_time_from_system())) == 0)
	return DomainResult.ok(view)


## 通过正式导航提交移动；模型不能修改实时位置。
## [param actor] 本模块角色。[param target] 希望抵达的坐标。
## 返回权威移动结果。
func move(actor: AiPlayerActor, target: Vector2) -> DomainResult:
	var map := _map(actor)
	if map == null: return DomainResult.failure(&"ai.session_lost", "AI会话已失效")
	return _result(_server.handle_peer_move(actor.peer_id, MoveIntent.new(map.instance_id, target, actor.next_sequence()).to_dictionary()))


## 将白名单行动映射到与真人相同的命令入口，并在执行时读取最新版本。
## [param actor] 本模块角色。[param action] 类型化行动。[param target] 重新观察的目标。
## 返回实际事务结果。
func perform(actor: AiPlayerActor, action: AiPlayerAction, target: AiPlayerObservation.Target) -> DomainResult:
	var map := _map(actor)
	if map == null: return DomainResult.failure(&"ai.session_lost", "AI会话已失效")
	var raw: Dictionary
	match action.kind:
		"hunt", "mine", "self_repair":
			var ability := action.ability_id if action.kind == "hunt" else ("mining.collect" if action.kind == "mine" else "self_repair")
			var aim: Vector2 = target.position if target != null else map.entities[actor.entity_id].position
			raw = _server.handle_peer_use_ability(actor.peer_id, UseAbilityIntent.new(map.instance_id, ability, aim, actor.next_sequence()).to_dictionary())
		"travel":
			var selected: MapTransition
			for transition: MapTransition in map.definition.enabled_transitions():
				if String(transition.transition_id) == action.target_id: selected = transition
			if selected == null: return DomainResult.failure(&"ai.target_lost", "传送点已失效")
			raw = _server.handle_peer_map_transition(actor.peer_id, MapTransitionIntent.new(map.instance_id, action.target_id, selected.destination_entry_number, actor.next_sequence()).to_dictionary())
		"return_base":
			raw = _server.handle_peer_vehicle_recovery(actor.peer_id, VehicleRecoveryIntent.new(map.instance_id, "return_to_base", actor.next_sequence()).to_dictionary())
		"pickup": raw = _server.handle_peer_loot_pickup(actor.peer_id, {"loot_id": action.target_id})
		"harvest", "panel":
			var command := action.panel_command.duplicate(true) if action.kind == "panel" else {"type": "harvest_garden", "plant_id": action.target_id}
			var state := _server.autosave_service.state_for(actor.entity_id)
			command.merge({"inventory_revision": state.inventory_revision, "loadout_revision": state.vehicle_loadout_revision,
				"state_revision": state.revision, "production_revision": state.production.revision}, true)
			if command.type == "cancel_production": command["confirm_cancel"] = true
			raw = _server.handle_peer_player_panel_command(actor.peer_id, command)
		_: return DomainResult.failure(&"ai.unsupported", "未接入的AI行动")
	return _result(raw)


## 保存并释放自己的会话；失败会明确报告而不是操作其他玩家。
## [param actor] 待关闭的独立角色。
## 返回保存和释放结果。
func close_actor(actor: AiPlayerActor) -> DomainResult:
	if _map(actor) == null: return DomainResult.ok()
	var closed := _result(_server.handle_peer_player_panel_command(actor.peer_id,
		{"type": "prepare_exit", "request_id": Crypto.new().generate_random_bytes(16).hex_encode()}))
	if not closed.is_ok:
		move(actor, _map(actor).entities[actor.entity_id].position)
		_server.disconnect_session(actor.peer_id)
	_owned.erase(actor.peer_id)
	return closed


## 验证对象所有权与当前会话，阻止调用方借端口操纵真人角色。
## [param actor] 本模块角色对象。
## 返回有效地图或空值。
func _map(actor: AiPlayerActor) -> AuthoritativeMapInstance:
	if actor == null or _owned.get(actor.peer_id) != actor: return null
	var session := _server.sessions.session_for_peer(actor.peer_id)
	if session == null or session.entity_id != actor.entity_id: return null
	var map := _server.map_registry.instance_by_id(session.map_instance_id)
	return map if map != null and map.entities.has(actor.entity_id) else null


## 添加受半径及数量限制的目标，不构造整个地图网络快照。
## [param view] 当前观察。[param kind] 类别。[param id] 身份。[param label] 名称。
## [param position] 坐标。[param health] 生命。[param available] 可用性。[param nearby] 是否限制半径。
func _add(view: AiPlayerObservation, kind: String, id: String, label: String, position: Vector2, health := 0, available := true, nearby := true) -> void:
	if nearby and view.position.distance_to(position) > _radius: return
	if not view.targets.has(kind): view.targets[kind] = []
	if view.targets[kind].size() >= 32: return
	var target := AiPlayerObservation.Target.new()
	target.id = id
	target.name = label
	target.position = position
	target.health = health
	target.available = available
	view.targets[kind].append(target)


## 查询目录名称，不暴露素材路径或整个物品目录。
## [param id] 物品定义身份。
## 返回显示名。
func _item_name(id: String) -> String:
	return String(_server.player_panel_service.item_catalog().definition(id).get("display_name", id))


## 转换已有服务器协议结果，不改变成功失败语义。
## [param raw] 权威结果。
## 返回领域结果。
func _result(raw: Dictionary) -> DomainResult:
	return DomainResult.ok(raw.get("value")) if raw.get("ok", false) else DomainResult.failure(StringName(raw.get("code", "ai.failed")), String(raw.get("message", "行动失败")))
