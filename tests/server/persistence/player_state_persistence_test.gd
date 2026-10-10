extends SceneTree

const DomainResult := preload("res://scripts/core/domain_result.gd")
const FileRepositoryScript := preload("res://scripts/server/persistence/file_player_state_repository.gd")
const SqliteDriverPortScript := preload("res://scripts/server/persistence/sqlite_driver_port.gd")
const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
const SQL_MIGRATION_PATH := "res://data/server/persistence/migrations/001_initial.sql"
const SKILL_MIGRATION_PATH := "res://data/server/persistence/migrations/002_skill_progression.sql"
const TEST_DIRECTORY := "res://"

var failures: Array[String] = []
var assertions := 0
var database_path := ""
var fixture: PlayerPanelServiceFixture


## 初始化当前模块或独立测试夹具。
func _initialize() -> void:
	fixture = Fixture.new()
	_expect(fixture.initialize().is_ok, "current-schema player fixture should initialize")
	database_path = TEST_DIRECTORY.path_join(
		"player_state_%d_%d.tmp" % [OS.get_process_id(), Time.get_ticks_msec()]
	)
	_test_sqlite_runtime_and_schema_seam()
	_test_inventory_position_required()
	_test_atomic_transaction_and_reload()
	_cleanup_test_files()
	if failures.is_empty():
		print("PLAYER_STATE_PERSISTENCE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 执行 `test_sqlite_runtime_and_schema_seam` 对应的模块操作。
func _test_sqlite_runtime_and_schema_seam() -> void:
	var capability: Dictionary = SqliteDriverPortScript.runtime_capability()
	_expect(not bool(capability["available"]), "bundled Godot 4.7 runtime should not claim an unavailable SQLite driver")
	_expect(capability["adapter_status"] == &"driver_adapter_required", "runtime capability should require an explicit driver adapter")
	var unavailable := SqliteDriverPortScript.new().open_database("user://never-opened.sqlite3")
	_expect(not unavailable.is_ok and unavailable.error_code == &"persistence.sqlite_driver_unavailable", "base SQLite port must fail explicitly")
	_expect(FileAccess.file_exists(SQL_MIGRATION_PATH), "production SQLite schema migration should be versioned")
	_expect(FileAccess.file_exists(SKILL_MIGRATION_PATH), "skill progression SQLite migration should be versioned")
	var sql := FileAccess.get_file_as_string(SQL_MIGRATION_PATH)
	for table_name: String in [
		"accounts", "characters", "character_skills", "inventory_stacks", "equipment_slots", "vehicles",
		"character_locations", "command_receipts",
	]:
		_expect(sql.contains("CREATE TABLE IF NOT EXISTS %s" % table_name), "SQL migration should define %s" % table_name)


func _test_inventory_position_required() -> void:
	var raw: Dictionary = _fixture_state().inventory_stacks[0].to_dictionary()
	raw.erase("position_px")
	var decoded := InventoryStackRecord.from_dictionary(raw)
	_expect(not decoded.is_ok, "inventory position must be present in current records")


## 执行 `test_atomic_transaction_and_reload` 对应的模块操作。
func _test_atomic_transaction_and_reload() -> void:
	var repository: FilePlayerStateRepository = FileRepositoryScript.new(database_path)
	var initialized := repository.initialize()
	_expect(initialized.is_ok, "fresh development repository should initialize")
	if not initialized.is_ok:
		return
	var created := repository.create_player(_fixture_state())
	_expect(created.is_ok and int(created.value.revision) == 0, "new player should commit at revision zero")
	if not created.is_ok:
		return
	var committed := repository.transact_player(
		"character.tomato", Callable(self, "_apply_checkpoint_transaction")
	)
	_expect(committed.is_ok and int(committed.value.revision) == 1, "successful transaction should increment revision once")
	if not committed.is_ok:
		return
	_expect(int(committed.value.inventory_revision) == 1, "inventory mutation should persist its own revision")
	_expect(committed.value.map_instance_id == "d04.instance.7", "map instance should commit with the aggregate")
	var aborted := repository.transact_player(
		"character.tomato", Callable(self, "_abort_after_mutation")
	)
	_expect(not aborted.is_ok and aborted.error_code == &"test.forced_rollback", "callback failure should abort the transaction")
	var after_abort := repository.load_player("character.tomato")
	_expect(after_abort.is_ok and int(after_abort.value.revision) == 1, "aborted transaction must not increment revision")
	_expect(int(after_abort.value.inventory_stacks[0].quantity) == 8, "aborted mutation must not leak into repository state")
	var stale_candidate: PlayerStateRecord = after_abort.value.duplicate_record()
	stale_candidate.vehicle_health = 1
	var stale := repository.save_player(stale_candidate, 0)
	_expect(not stale.is_ok and stale.error_code == &"persistence.revision_conflict", "stale optimistic save should be rejected")
	var after_stale := repository.load_player("character.tomato")
	_expect(int(after_stale.value.vehicle_health) == 55, "stale save must not mutate committed vehicle state")
	var reloaded_repository: FilePlayerStateRepository = FileRepositoryScript.new(database_path)
	_expect(reloaded_repository.initialize().is_ok, "new repository instance should reopen committed storage")
	var restored := reloaded_repository.load_player("character.tomato")
	_expect(restored.is_ok, "disconnect/reconnect reload should recover the character")
	_expect(restored.value.map_id == "glory_nft_bl_d04" and restored.value.map_instance_id == "d04.instance.7", "reload should restore location and map instance")
	_expect(restored.value.position == Vector2(1200.0, 1200.0), "reload should restore authoritative position")
	_expect(int(restored.value.vehicle_health) == 55, "reload should restore vehicle combat state")
	_expect(int(restored.value.inventory_stacks[0].quantity) == 8, "reload should restore committed inventory stacks")
	_expect(restored.value.equipment_slots[0].item_instance_id == "equipment.cannon.1", "reload should restore equipped item instances")
	_expect(int(restored.value.character_skills.get("energy_cannon", {}).get("level", 0)) == 10,
		"重载应恢复人物技能等级")


## 执行 `apply_checkpoint_transaction` 对应的模块操作。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _apply_checkpoint_transaction(state: PlayerStateRecord) -> DomainResult:
	state.map_id = "glory_nft_bl_d04"
	state.map_instance_id = "d04.instance.7"
	state.position = Vector2(1200.0, 1200.0)
	state.facing_direction = 3
	state.vehicle_health = 55
	state.inventory_stacks[0].quantity = 8
	state.inventory_revision += 1
	return DomainResult.ok()


## 执行 `abort_after_mutation` 对应的模块操作。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _abort_after_mutation(state: PlayerStateRecord) -> DomainResult:
	state.inventory_stacks[0].quantity = 999
	state.vehicle_health = 1
	state.position = Vector2(9999.0, 9999.0)
	return DomainResult.failure(&"test.forced_rollback", "forced transaction rollback")


## 执行 `fixture_state` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func _fixture_state() -> PlayerStateRecord:
	var state: PlayerStateRecord = fixture._state.duplicate_record()
	state.account_id = "account.tomato"
	state.account_name = "tomato"
	state.character_id = "character.tomato"
	state.display_name = "H番茄花园"
	state.inventory_stacks = [state.inventory_stacks[0].duplicate_record()]
	state.inventory_stacks[0].stack_id = "stack.iron.1"
	state.inventory_stacks[0].quantity = 5
	var weapon := state.equipment_slots[1].duplicate_record()
	weapon.item_instance_id = "equipment.cannon.1"
	state.equipment_slots = [weapon]
	state.character_health = 100
	state.character_max_health = 100
	state.vehicle_health = 70
	state.vehicle_max_health = 70
	state.vehicle_id = "vehicle.tomato.1"
	state.map_instance_id = "RoomSvr1.instance.1"
	state.position = Vector2(730, 1330)
	state.checkpoint_id = "hall.default"
	var validation := state.validate()
	_expect(validation.is_ok, "persistence fixture should satisfy aggregate invariants")
	return state


## 移除并清理 `cleanup_test_files` 对应的模块状态。
func _cleanup_test_files() -> void:
	for path: String in [
		database_path, database_path + ".tmp", database_path + ".bak",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for old_version: int in [0, 1, 2]:
		var old_path := database_path.replace(
			"player_state_", "player_state_old_%d_" % old_version
		)
		for path: String in [old_path, old_path + ".tmp", old_path + ".bak"]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
