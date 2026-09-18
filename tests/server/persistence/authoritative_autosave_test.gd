extends SceneTree

const ConfigScript := preload("res://scripts/server/server_config.gd")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")
const RepositoryScript := preload("res://scripts/server/persistence/file_player_state_repository.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")

var failures: Array[String] = []
var assertions := 0
var database_path := ""


## 运行三秒自动存档与服务器重建恢复测试，并按断言结果设置进程退出码。
func _initialize() -> void:
	database_path = "res://authoritative_autosave_%d_%d.tmp" % [
		OS.get_process_id(), Time.get_ticks_msec(),
	]
	_test_three_second_authoritative_autosave()
	_cleanup_test_files()
	if failures.is_empty():
		print("AUTHORITATIVE_AUTOSAVE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 验证服务器只在满三秒时采集权威状态，并能在新进程语义下恢复已提交聚合。
## 设计：测试直接修改服务端实体与战斗状态，不经客户端载荷，从而证明持久化数据源属于权威服务器。
func _test_three_second_authoritative_autosave() -> void:
	var first_server = ServerScript.new()
	var first_config = _server_config()
	var initialized: Dictionary = first_server.initialize(first_config)
	_expect(initialized.ok, "启用持久化的 D04 权威服务器应初始化")
	if not initialized.ok:
		return
	var opened: Dictionary = first_server.open_session(71, _handshake(), 1000)
	_expect(opened.ok, "首个角色会话应建立并创建 revision 0 存档")
	if not opened.ok:
		return
	var entity_id: String = opened.value.session.entity_id
	var first_loaded = first_server.player_state_repository.load_player(entity_id)
	_expect(first_loaded.is_ok and first_loaded.value.revision == 0, "建号只应提交 revision 0")

	first_server.advance_simulation(2.99, 3990)
	var before_deadline = first_server.player_state_repository.load_player(entity_id)
	_expect(before_deadline.is_ok and before_deadline.value.revision == 0, "未满三秒不得提前自动存档")

	var entity: AuthoritativeEntity = first_server.map_instance.entities[entity_id]
	var persisted_position: Vector2 = entity.position
	entity.facing_index = 5
	var combat_state: VehicleCombatState = first_server.map_instance.vehicle_combat_state_for(entity_id)
	_expect(combat_state != null, "D04 玩家应拥有服务端战车资源状态")
	if combat_state == null:
		return
	combat_state.health = maxi(1, combat_state.max_health - 11)
	combat_state.reserve_energy = maxf(0.0, combat_state.reserve_energy_capacity - 17.0)
	combat_state.working_energy = maxf(0.0, combat_state.working_energy_capacity - 9.0)
	first_server.advance_simulation(0.01, 4000)
	var expected_health := combat_state.health
	var expected_reserve := combat_state.reserve_energy
	var expected_working := combat_state.working_energy
	var committed = first_server.player_state_repository.load_player(entity_id)
	_expect(committed.is_ok and committed.value.revision == 1, "满三秒应由服务器提交一次存档")
	if not committed.is_ok:
		return
	_expect(committed.value.position.is_equal_approx(persisted_position), "存档应采集权威实体位置")
	_expect(committed.value.facing_direction == 5, "存档应采集权威实体朝向")
	_expect(committed.value.vehicle_health == expected_health, "存档应采集权威战车生命")
	_expect(is_equal_approx(committed.value.reserve_energy, expected_reserve), "存档应采集权威储备能量")
	_expect(is_equal_approx(committed.value.working_energy, expected_working), "存档应采集权威当前能量")

	var panel_query: Dictionary = first_server.handle_peer_player_panel_command(71, {"type": "query"})
	_expect(panel_query.ok, "已登录角色应能查询三面板权威快照")
	if panel_query.ok:
		var panel_bundle: Dictionary = panel_query.value
		_expect(panel_bundle.inventory.items.size() == 2, "新角色应有备用引擎和训练服")
		var panel_move: Dictionary = first_server.handle_peer_player_panel_command(71, {
			"type": "move_inventory_item",
			"instance_id": "inventory.%s.spare_engine" % entity_id,
			"position_px": [92, 61],
			"inventory_revision": int(panel_bundle.inventory.revision),
		})
		_expect(panel_move.ok, "背包移动应由权威服务器立即原子提交")
		var panel_committed = first_server.player_state_repository.load_player(entity_id)
		_expect(panel_committed.is_ok and panel_committed.value.revision == 2, "面板事务应立即推进玩家聚合 revision")
		_expect(panel_committed.value.inventory_stacks[0].position_px == Vector2i(92, 61), "面板事务应持久化原始自由像素坐标")

	var second_server = ServerScript.new()
	_expect(first_server.player_state_repository.flush().is_ok, "新实例读取前显式等待后台检查点完成")
	var reopened: Dictionary = second_server.initialize(_server_config())
	_expect(reopened.ok, "新服务器实例应重新打开同一存档")
	if not reopened.ok:
		return
	var resumed: Dictionary = second_server.open_session(72, _handshake(), 5000)
	_expect(resumed.ok and resumed.value.session.entity_id == entity_id, "重建后同一角色标识应载入既有聚合")
	if not resumed.ok:
		return
	var restored_entity: AuthoritativeEntity = second_server.map_instance.entities[entity_id]
	var restored_combat: VehicleCombatState = second_server.map_instance.vehicle_combat_state_for(entity_id)
	_expect(restored_entity.position.is_equal_approx(persisted_position), "新服务器应恢复已提交位置")
	_expect(restored_entity.facing_index == 5, "新服务器应恢复已提交朝向")
	_expect(restored_combat != null and restored_combat.health == expected_health, "新服务器应恢复战车生命")
	var restored_panel_state = second_server.player_state_repository.load_player(entity_id)
	_expect(
		restored_panel_state.is_ok \
		and restored_panel_state.value.inventory_stacks[0].position_px == Vector2i(92, 61),
		"服务器重建后应恢复背包像素布局",
	)
	_expect(
		restored_combat != null and is_equal_approx(restored_combat.reserve_energy, expected_reserve),
		"新服务器应恢复储备能量",
	)
	_expect(
		restored_combat != null and is_equal_approx(restored_combat.working_energy, expected_working),
		"新服务器应恢复当前能量",
	)

	var legacy_state_result = second_server.player_state_repository.load_player(entity_id)
	_expect(legacy_state_result.is_ok, "地图 ID 迁移夹具必须能读取现有角色")
	if legacy_state_result.is_ok:
		var legacy_state: PlayerStateRecord = legacy_state_result.value
		legacy_state.map_id = "glory_nft_bl_nasa1"
		legacy_state.map_instance_id = "glory_nft_bl_nasa1.instance.1"
		legacy_state.position = Vector2(1381.0, 918.0)
		var staged_legacy = second_server.player_state_repository.save_player(
			legacy_state, legacy_state.revision
		)
		_expect(staged_legacy.is_ok, "测试必须能写入业务化前的宇航中心地图 ID")
		if staged_legacy.is_ok:
			_expect(second_server.player_state_repository.flush().is_ok, "迁移重开前等待后台快照完成")
			var migrated_server = ServerScript.new()
			var migrated_initialized: Dictionary = migrated_server.initialize(
				_full_server_config()
			)
			_expect(migrated_initialized.ok, "完整地图目录服务器应接受旧地图存档")
			if migrated_initialized.ok:
				var migrated_session: Dictionary = migrated_server.open_session(
					73, _handshake(), 6000
				)
				_expect(migrated_session.ok, "旧地图 ID 不得阻塞角色会话恢复")
				if migrated_session.ok:
					_expect(
						String(migrated_session.value.map_joined.map_id) \
						== "dragon_city_space_center",
						"旧宇航中心 ID 必须迁移为当前业务地图 ID",
					)
					_expect(
						Vector2(
							migrated_session.value.map_joined.spawn_position.x,
							migrated_session.value.map_joined.spawn_position.y,
						).is_equal_approx(Vector2(1381.0, 918.0)),
						"地图 ID 迁移必须保留仍然可达的角色坐标",
					)
			migrated_server.free()
	first_server.free()
	second_server.free()


## 构造只加载 D04、禁用真实网络且启用三秒文件仓储的服务端配置。
func _server_config():
	var config := ConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = true
	config.player_state_store_path = database_path
	config.autosave_interval_seconds = 3.0
	config.map_config_path = "res://data/maps/d04_field_zone.json"
	config.map_catalog_path = "res://tests/fixtures/nonexistent_map_catalog.json"
	config.default_spawn = Vector2(2412.0, 2400.0)
	config.dynamic_blocking_enabled = false
	return config


## 构造包含当前业务化地图目录的进程内权威服务器配置。
## 返回使用同一测试仓储、但允许恢复宇航中心等正式地图的配置。
func _full_server_config():
	var config := ConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = true
	config.player_state_store_path = database_path
	config.autosave_interval_seconds = 3.0
	config.dynamic_blocking_enabled = false
	return config


## 构造与当前共享协议及内容版本一致的会话握手载荷。
## 返回该函数计算、查询或操作得到的结果。
func _handshake() -> Dictionary:
	return {
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"content_version": Protocol.PUBLIC_CONTENT_VERSION,
	}


## 删除本测试在项目根目录创建的主文件、临时文件与备份文件。
func _cleanup_test_files() -> void:
	for path: String in [database_path, database_path + ".tmp", database_path + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
