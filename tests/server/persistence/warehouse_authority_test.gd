extends SceneTree

class RejectingRepository extends PlayerStateRepository:
	## 模拟仓储提交失败，不改变原仓储内容。
	## [param _state] 不会被接受的候选。
	## [param _expected_revision] 调用方预期版本。
	## 返回可检查的写入失败。
	func save_player(_state: PlayerStateRecord, _expected_revision: int) -> DomainResult:
		return DomainResult.failure(&"test.write_failed", "模拟仓储写入失败")

const PEER := 93
var checks := 0
var failures: Array[String] = []


## 等场景树就绪后运行实际权威服务与独立存档。
func _initialize() -> void:
	call_deferred("_run")


## 经真实会话提交扩容、部分存入、故障、重发和重启取出。
func _run() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = "res://data/maps/yian_harbor_hall_floor_1.json"
	config.player_state_store_path = "res://.godot/warehouse-authority-%d.json" % Time.get_ticks_usec()
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "服务器")
	_check(server.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok, "会话")
	var session := server.sessions.session_for_peer(PEER)
	var catalog := ItemCatalog.new()
	_check(catalog.initialize().is_ok, "目录")
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(server.autosave_service.state_for(session.entity_id)).value
	player.amethyst = AmethystWallet.new(5000)
	player.inventory.add_reward(catalog.create("bright_firepower_crystal", {"instance_id": "test.crystal", "quantity": 7, "bound": true, "crystal_cracks": 2}).value)
	_check(server.autosave_service.commit_player_state(session.entity_id, mapper.to_record(player).value).is_ok, "隔离测试物品")
	var state := server.autosave_service.state_for(session.entity_id)
	_test_rejections(server.warehouse_service, state)
	var query := server.handle_peer_player_panel_command(PEER, {"type": "query_personal_warehouse"})
	_check(query.ok and query.value.personal_warehouse.cabinet_count == 1, "权威查询")
	var expand := _command("expand_personal_warehouse", state)
	expand["confirm_expansion"] = true
	expand["price"] = 0
	var expanded := server.handle_peer_player_panel_command(PEER, expand)
	_check(expanded.ok and expanded.value.personal_warehouse.cabinet_count == 2 and expanded.value.personal_warehouse.amethyst == 3112, "扩容不相信客户端费用")
	_check(not server.handle_peer_player_panel_command(PEER, expand).ok, "扩容重复意图拒绝")
	state = server.autosave_service.state_for(session.entity_id)
	var deposit := _command("deposit_warehouse_item", state)
	deposit["cabinet"] = 2
	deposit["instance_id"] = "test.crystal"
	deposit["quantity"] = 3
	deposit["split_id"] = "test.crystal"
	var real_repository := server.autosave_service._repository
	server.autosave_service._repository = RejectingRepository.new()
	var before := state.to_dictionary()
	var rejected := server.handle_peer_player_panel_command(PEER, deposit)
	_check(not rejected.ok, "提交失败返回拒绝")
	_check(server.autosave_service.state_for(session.entity_id).to_dictionary() == before, "提交失败背包仓库同时不变")
	server.autosave_service._repository = real_repository
	var deposited := server.handle_peer_player_panel_command(PEER, deposit)
	_check(deposited.ok and deposited.value.personal_warehouse.items.size() == 1 and deposited.value.personal_warehouse.items[0].amount == 3, "实际存入三颗")
	_check(not server.handle_peer_player_panel_command(PEER, deposit).ok, "重复存入拒绝")
	state = server.autosave_service.state_for(session.entity_id)
	_check(deposited.value.transaction_revision == state.revision, "下发最终提交版本")
	var item_id: String = deposited.value.personal_warehouse.items[0].instance_id
	_check(item_id != "test.crystal", "部分存取身份由服务器生成")
	_check(not server.handle_peer_player_panel_command(999, deposit).ok, "未绑定会话不能存取")
	server._save_all_persistent_players()
	server.free()
	var restarted := AuthoritativeServer.new()
	_check(restarted.initialize(config).ok, "服务器重启")
	_check(restarted.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok, "重新连接")
	session = restarted.sessions.session_for_peer(PEER)
	query = restarted.handle_peer_player_panel_command(PEER, {"type": "query_personal_warehouse", "cabinet": 2})
	_check(query.ok and query.value.personal_warehouse.items[0].instance_id == item_id and query.value.personal_warehouse.items[0].crystal_cracks == 2, "重启保留部分堆叠身份和裂纹")
	state = restarted.autosave_service.state_for(session.entity_id)
	var withdraw := _command("withdraw_warehouse_item", state)
	withdraw.merge({"cabinet": 2, "instance_id": item_id, "quantity": 3}, true)
	var withdrawn := restarted.handle_peer_player_panel_command(PEER, withdraw)
	_check(withdrawn.ok and withdrawn.value.personal_warehouse.items.is_empty(), "取回清除仓库堆叠")
	player = mapper.to_domain(restarted.autosave_service.state_for(session.entity_id)).value
	_check(player.inventory.find("test.crystal").quantity == 7 and player.amethyst.balance() == 3112, "两侧数量及钱包守恒")
	restarted.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	print("Warehouse authority: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 检查不可信数量、费用、地点与扩容确认，失败不能污染输入存档。
## [param service] 真实仓库服务。
## [param state] 基地玩家的已提交状态。
func _test_rejections(service: PersonalWarehouseService, state: PlayerStateRecord) -> void:
	var command := _command("deposit_warehouse_item", state)
	command["instance_id"] = "test.crystal"
	var before := state.to_dictionary()
	for count: Variant in [0, -1, 8, 1.5, true, "3", INF]:
		command["quantity"] = count
		_check(not service.execute(state, command).is_ok and state.to_dictionary() == before, "拒绝无效数量")
	command["quantity"] = 1
	var field := state.duplicate_record()
	field.map_id = "d04_field_zone"
	command["map_id"] = "yian_harbor_city"
	_check(not service.execute(field, command).is_ok, "伪造允许地点无效")
	var query := service.execute(field, {"type": "query_personal_warehouse"})
	_check(query.is_ok and not query.value.panel_bundle.personal_warehouse.available and query.value.panel_bundle.personal_warehouse.items.is_empty(), "野外显示限制，不加载物品")
	_check(not service.execute(state, _command("expand_personal_warehouse", state)).is_ok, "扩容需要确认")
	var empty := state.duplicate_record()
	empty.amethyst = 1887
	var expand := _command("expand_personal_warehouse", empty)
	expand["confirm_expansion"] = true
	_check(not service.execute(empty, expand).is_ok and empty.amethyst == 1887, "余额不足不扣费")


## 构造仅携带库存版本的测试意图。
## [param kind] 已知命令类型。
## [param state] 当前已提交的权威状态。
## 返回独立字典。
func _command(kind: String, state: PlayerStateRecord) -> Dictionary:
	return {"type": kind, "cabinet": 1, "inventory_revision": state.inventory_revision, "warehouse_revision": state.warehouse.revision()}


## 汇总权威事务检查。
## [param condition] 实际条件。
## [param message] 失败描述。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
