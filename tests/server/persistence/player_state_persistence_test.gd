extends SceneTree

const DomainResult := preload("res://scripts/core/domain_result.gd")
const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")
const FileRepositoryScript := preload("res://scripts/server/persistence/file_player_state_repository.gd")
const SqliteDriverPortScript := preload("res://scripts/server/persistence/sqlite_driver_port.gd")
const SQL_MIGRATION_PATH := "res://data/server/persistence/migrations/001_initial.sql"
const SKILL_MIGRATION_PATH := "res://data/server/persistence/migrations/002_skill_progression.sql"
const TEST_DIRECTORY := "res://"

var failures: Array[String] = []
var assertions := 0
var database_path := ""


## 初始化当前模块或独立测试夹具。
func _initialize() -> void:
	database_path = TEST_DIRECTORY.path_join(
		"player_state_%d_%d.tmp" % [OS.get_process_id(), Time.get_ticks_msec()]
	)
	_test_sqlite_runtime_and_schema_seam()
	_test_schema_zero_migration()
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


## 执行 `test_schema_zero_migration` 对应的模块操作。
func _test_schema_zero_migration() -> void:
	var migration_path := database_path.replace("player_state_", "player_state_migration_")
	var state: PlayerStateRecord = _fixture_state()
	var legacy := {
		"schema_version": 0,
		"characters": {state.character_id: state.to_dictionary()},
	}
	var file := FileAccess.open(migration_path, FileAccess.WRITE)
	_expect(file != null, "migration fixture should open")
	if file == null:
		return
	file.store_string(JSON.stringify(legacy))
	file.close()
	var repository: FilePlayerStateRepository = FileRepositoryScript.new(migration_path)
	var initialized := repository.initialize()
	_expect(initialized.is_ok, "schema-zero file should migrate during initialization")
	_expect(repository.current_schema_version() == 2, "repository should expose migrated schema two")
	var loaded := repository.load_player(state.character_id)
	_expect(loaded.is_ok and loaded.value.display_name == state.display_name, "migrated player aggregate should remain loadable")
	var migrated_root: Variant = JSON.parse_string(FileAccess.get_file_as_string(migration_path))
	_expect(migrated_root is Dictionary and int(migrated_root["schema_version"]) == 2, "migration should be materialized to disk")
	_expect(migrated_root.has("players") and not migrated_root.has("characters"), "migration should replace the legacy aggregate key")


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
	_expect(restored.value.map_id == "d04_field_zone" and restored.value.map_instance_id == "d04.instance.7", "reload should restore location and map instance")
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
	state.map_id = "d04_field_zone"
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
	var result := PlayerStateRecordScript.from_dictionary({
		"schema_version": PlayerStateRecord.CURRENT_SCHEMA_VERSION,
		"account_id": "account.tomato",
		"account_name": "tomato",
		"account_status": "active",
		"character_id": "character.tomato",
		"display_name": "H番茄花园",
		"revision": 0,
		"inventory_revision": 0,
		"inventory_capacity": 40,
		"inventory_stacks": [{
			"stack_id": "stack.iron.1",
			"item_definition_id": "item.material.iron",
			"quantity": 5,
			"slot_index": 0,
		}],
		"equipment_slots": [{
			"owner_kind": "vehicle",
			"slot_id": "primary_weapon",
			"item_instance_id": "equipment.cannon.1",
			"item_definition_id": "recruit_energy_cannon",
			"max_durability": 900,
			"durability": 900,
			"upgrade_level": 0,
		}],
		"character_max_health": 100,
		"character_health": 100,
		"character_experience": 0,
		"character_skills": {
			"energy_cannon": {"level": 10, "current_exp": 4, "fractional_exp": 0.5},
			"driving": {"level": 10, "current_exp": 0, "fractional_exp": 0.0},
		},
		"vehicle_id": "vehicle.tomato.1",
		"vehicle_definition_id": "recruit_tank",
		"vehicle_max_health": 70,
		"vehicle_health": 70,
		"reserve_energy_capacity": 10000,
		"reserve_energy": 10000,
		"working_energy_capacity": 100,
		"working_energy": 100,
		"output_power": 21,
		"map_id": "yian_harbor_hall_floor_1",
		"map_instance_id": "RoomSvr1.instance.1",
		"position": [730, 1330],
		"facing_direction": 0,
		"checkpoint_id": "hall.default",
	})
	_expect(result.is_ok, "persistence fixture should satisfy aggregate invariants")
	return result.value


## 移除并清理 `cleanup_test_files` 对应的模块状态。
func _cleanup_test_files() -> void:
	var migration_path := database_path.replace("player_state_", "player_state_migration_")
	for path: String in [
		database_path, database_path + ".tmp", database_path + ".bak",
		migration_path, migration_path + ".tmp", migration_path + ".bak",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
