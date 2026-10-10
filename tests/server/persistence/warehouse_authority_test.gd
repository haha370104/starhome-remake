extends SceneTree

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
	var current: Player = server.autosave_service.player_for(session.entity_id)
	var copied := mapper.to_record(current)
	_check(copied.is_ok, "复制初始玩家")
	if not copied.is_ok: return
	var player_result := mapper.to_domain(copied.value)
	_check(player_result.is_ok, "还原初始玩家")
	if not player_result.is_ok: return
	var player: Player = player_result.value
	player.amethyst = AmethystWallet.new(5000)
	player.inventory.add_reward(catalog.create("bright_firepower_crystal", {"instance_id": "test.crystal", "quantity": 7, "bound": true, "crystal_cracks": 2}).value)
	_check(server.autosave_service.commit_player(session.entity_id, player, true).is_ok, "隔离测试物品")
	var state: PlayerStateRecord = mapper.to_record(server.autosave_service.player_for(session.entity_id)).value
	var query := server.handle_peer_player_panel_command(PEER, {"type": "query_personal_warehouse"})
	_check(query.ok and query["value"]["personal_warehouse"]["cabinet_count"] == 1, "权威查询")
	var expand := _command("expand_personal_warehouse", state)
	expand["confirm_expansion"] = true
	expand["price"] = 0
	var expanded := server.handle_peer_player_panel_command(PEER, expand)
	_check(expanded.ok and expanded["value"]["personal_warehouse"]["cabinet_count"] == 2 \
		and expanded["value"]["personal_warehouse"]["amethyst"] == 3112, "扩容不相信客户端费用")
	_check(not server.handle_peer_player_panel_command(PEER, expand).ok, "扩容重复意图拒绝")
	state = mapper.to_record(server.autosave_service.player_for(session.entity_id)).value
	var deposit := _command("deposit_warehouse_item", state)
	deposit["cabinet"] = 2
	deposit.merge({"instance_id": "test.crystal", "position_px": [117, 139]})
	var deposited := server.handle_peer_player_panel_command(PEER, deposit)
	_check(deposited.ok, "实际整堆存入")
	if not deposited.ok:
		push_error("warehouse deposit failed: %s" % deposited)
		return
	_check(deposited["value"]["personal_warehouse"]["items"].size() == 1 \
		and deposited["value"]["personal_warehouse"]["items"][0]["amount"] == 7, "实际整堆存入")
	_check(not server.handle_peer_player_panel_command(PEER, deposit).ok, "重复存入拒绝")
	state = mapper.to_record(server.autosave_service.player_for(session.entity_id)).value
	_check(deposited["value"]["transaction_revision"] == state.revision, "下发最终提交版本")
	var item_id: String = deposited["value"]["personal_warehouse"]["items"][0]["instance_id"]
	_check(item_id == "test.crystal", "整堆存取保留身份")
	_check(not server.handle_peer_player_panel_command(999, deposit).ok, "未绑定会话不能存取")
	server._save_all_persistent_players()
	server.free()
	var restarted := AuthoritativeServer.new()
	_check(restarted.initialize(config).ok, "服务器重启")
	_check(restarted.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok, "重新连接")
	session = restarted.sessions.session_for_peer(PEER)
	query = restarted.handle_peer_player_panel_command(PEER, {"type": "query_personal_warehouse", "cabinet": 2})
	_check(query.ok and query["value"]["personal_warehouse"]["items"][0]["instance_id"] == item_id \
		and query["value"]["personal_warehouse"]["items"][0]["crystal_cracks"] == 2 \
		and query["value"]["personal_warehouse"]["items"][0]["position_px"] == [117, 139], "重启保留身份、裂纹和自由落点")
	state = mapper.to_record(restarted.autosave_service.player_for(session.entity_id)).value
	var withdraw := _command("withdraw_warehouse_item", state)
	withdraw.merge({"cabinet": 2, "instance_id": item_id, "position_px": [91, 103]}, true)
	var withdrawn := restarted.handle_peer_player_panel_command(PEER, withdraw)
	_check(withdrawn.ok and withdrawn["value"]["personal_warehouse"]["items"].is_empty(), "取回清除仓库堆叠")
	player = restarted.autosave_service.player_for(session.entity_id)
	_check(player.inventory.find("test.crystal").quantity == 7 and player.amethyst.balance() == 3112 \
		and player.inventory.find("test.crystal").position_px == Vector2i(91, 103), "数量及钱包守恒，取回不吸附")
	restarted.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	print("Warehouse authority: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

## 构造仅携带库存和仓库版本的测试意图。
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
