class_name FilePlayerStateRepository
extends PlayerStateRepository

const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")
const Migrator := preload("res://scripts/server/persistence/persistence_schema_migrator.gd")

var database_path := ""
var _schema_version := 0
var _players: Dictionary = {}
var _initialized := false


## 使用调用方参数初始化当前实例。
## [param requested_database_path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _init(requested_database_path: String = "") -> void:
	database_path = requested_database_path


## 配置并初始化 `initialize` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func initialize() -> DomainResult:
	if database_path.is_empty():
		return DomainResult.failure(&"persistence.invalid_database_path", "file repository path is empty")
	var recovered := _recover_interrupted_commit()
	if not recovered.is_ok:
		return recovered
	var storage_path := _native_storage_path()
	var raw_document: Dictionary
	if FileAccess.file_exists(storage_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(storage_path))
		if not parsed is Dictionary:
			return DomainResult.failure(&"persistence.invalid_database", "file repository root is not valid JSON object")
		raw_document = parsed
	else:
		raw_document = {"schema_version": Migrator.CURRENT_SCHEMA_VERSION, "players": {}, "migration_history": []}
	var migrated := Migrator.migrate_document(raw_document)
	if not migrated.is_ok:
		return migrated
	var loaded_players_result := _decode_players(migrated.value["players"])
	if not loaded_players_result.is_ok:
		return loaded_players_result
	var persist_result := _persist_document(migrated.value)
	if not persist_result.is_ok:
		return persist_result
	_schema_version = int(migrated.value["schema_version"])
	_players = loaded_players_result.value
	_initialized = true
	return DomainResult.ok(self)


## 执行 `create_player` 对应的模块操作。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func create_player(state: PlayerStateRecord) -> DomainResult:
	var ready := _require_initialized()
	if not ready.is_ok:
		return ready
	var validation := state.validate()
	if not validation.is_ok:
		return validation
	if _players.has(state.character_id):
		return DomainResult.failure(&"persistence.character_exists", "character already exists")
	if state.revision != 0:
		return DomainResult.failure(&"persistence.revision_conflict", "new character revision must be zero")
	var candidate := _duplicate_player_index(_players)
	candidate[state.character_id] = state.duplicate_record()
	return _commit_candidate(candidate, state.character_id)


## 执行 `load_player` 对应的模块操作。
## [param character_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func load_player(character_id: String) -> DomainResult:
	var ready := _require_initialized()
	if not ready.is_ok:
		return ready
	if not _players.has(character_id):
		return DomainResult.failure(&"persistence.character_not_found", "character does not exist")
	return DomainResult.ok((_players[character_id] as PlayerStateRecord).duplicate_record())


## 执行 `save_player` 对应的模块操作。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param expected_revision] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func save_player(state: PlayerStateRecord, expected_revision: int) -> DomainResult:
	var ready := _require_initialized()
	if not ready.is_ok:
		return ready
	if not _players.has(state.character_id):
		return DomainResult.failure(&"persistence.character_not_found", "character does not exist")
	var persisted: PlayerStateRecord = _players[state.character_id]
	if expected_revision < 0 or persisted.revision != expected_revision:
		return DomainResult.failure(&"persistence.revision_conflict", "player state revision changed")
	var candidate_state := state.duplicate_record()
	candidate_state.revision = expected_revision + 1
	var validation := candidate_state.validate()
	if not validation.is_ok:
		return validation
	var candidate := _duplicate_player_index(_players)
	candidate[state.character_id] = candidate_state
	return _commit_candidate(candidate, state.character_id)


## 执行 `transact_player` 对应的模块操作。
## [param character_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param operation] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func transact_player(character_id: String, operation: Callable) -> DomainResult:
	if not operation.is_valid():
		return DomainResult.failure(&"persistence.invalid_transaction", "transaction callback is invalid")
	var loaded := load_player(character_id)
	if not loaded.is_ok:
		return loaded
	var working: PlayerStateRecord = loaded.value
	var expected_revision := working.revision
	var operation_result: Variant = operation.call(working)
	if not operation_result is DomainResult:
		return DomainResult.failure(&"persistence.invalid_transaction", "transaction callback must return DomainResult")
	if not operation_result.is_ok:
		return operation_result
	return save_player(working, expected_revision)


## 执行 `current_schema_version` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func current_schema_version() -> int:
	return _schema_version


## 执行 `commit_candidate` 对应的模块操作。
## [param candidate] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param committed_character_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _commit_candidate(candidate: Dictionary, committed_character_id: String) -> DomainResult:
	var document := _encode_document(candidate)
	var persisted := _persist_document(document)
	if not persisted.is_ok:
		return persisted
	_players = candidate
	return DomainResult.ok((_players[committed_character_id] as PlayerStateRecord).duplicate_record())


## 执行 `persist_document` 对应的模块操作。
## [param document] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _persist_document(document: Dictionary) -> DomainResult:
	var storage_path := _native_storage_path()
	var absolute_directory := storage_path.get_base_dir()
	var make_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		return DomainResult.failure(&"persistence.storage_error", "cannot create database directory")
	var temporary_path := storage_path + ".tmp"
	var backup_path := storage_path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return DomainResult.failure(&"persistence.storage_error", "cannot open temporary database file")
	file.store_string(JSON.stringify(document, "  "))
	file.flush()
	file.close()
	var directory := DirAccess.open(absolute_directory)
	if directory == null:
		return DomainResult.failure(&"persistence.storage_error", "cannot open database directory")
	var database_name := storage_path.get_file()
	var temporary_name := temporary_path.get_file()
	var backup_name := backup_path.get_file()
	if directory.file_exists(backup_name):
		directory.remove(backup_name)
	var had_original := directory.file_exists(database_name)
	if had_original and directory.rename(database_name, backup_name) != OK:
		return DomainResult.failure(&"persistence.storage_error", "cannot stage previous database snapshot")
	if directory.rename(temporary_name, database_name) != OK:
		if had_original:
			directory.rename(backup_name, database_name)
		return DomainResult.failure(&"persistence.storage_error", "cannot install database snapshot")
	if had_original:
		directory.remove(backup_name)
	return DomainResult.ok()


## 执行 `recover_interrupted_commit` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func _recover_interrupted_commit() -> DomainResult:
	var storage_path := _native_storage_path()
	var backup_path := storage_path + ".bak"
	if FileAccess.file_exists(storage_path) or not FileAccess.file_exists(backup_path):
		return DomainResult.ok()
	var directory := DirAccess.open(storage_path.get_base_dir())
	if directory == null or directory.rename(backup_path.get_file(), storage_path.get_file()) != OK:
		return DomainResult.failure(&"persistence.storage_error", "cannot recover staged database backup")
	return DomainResult.ok()


## 将 Godot 虚拟资源路径转换为可执行原子重命名的原生文件系统路径。
## 返回 `res://`、`user://` 对应的绝对路径；原生路径保持不变。
## 设计：FileAccess 可以写虚拟路径，但 DirAccess 的资源视图不会立即发现新文件，提交过程必须统一使用原生路径。
func _native_storage_path() -> String:
	return ProjectSettings.globalize_path(database_path) \
		if database_path.begins_with("res://") or database_path.begins_with("user://") \
		else database_path


## 执行 `decode_players` 对应的模块操作。
## [param raw_players] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _decode_players(raw_players: Variant) -> DomainResult:
	if not raw_players is Dictionary:
		return DomainResult.failure(&"persistence.invalid_database", "players root must be a dictionary")
	var decoded: Dictionary = {}
	for raw_character_id: Variant in raw_players.keys():
		var result := PlayerStateRecordScript.from_dictionary(raw_players[raw_character_id])
		if not result.is_ok:
			return result
		var state: PlayerStateRecord = result.value
		if String(raw_character_id) != state.character_id or decoded.has(state.character_id):
			return DomainResult.failure(&"persistence.invalid_database", "player index identity is inconsistent")
		decoded[state.character_id] = state
	return DomainResult.ok(decoded)


## 执行 `encode_document` 对应的模块操作。
## [param players] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _encode_document(players: Dictionary) -> Dictionary:
	var serialized: Dictionary = {}
	for character_id: String in players:
		serialized[character_id] = (players[character_id] as PlayerStateRecord).to_dictionary()
	return {
		"schema_version": Migrator.CURRENT_SCHEMA_VERSION,
		"players": serialized,
		"migration_history": [1, 2],
	}


## 执行 `duplicate_player_index` 对应的模块操作。
## [param source] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _duplicate_player_index(source: Dictionary) -> Dictionary:
	var duplicate: Dictionary = {}
	for character_id: String in source:
		duplicate[character_id] = (source[character_id] as PlayerStateRecord).duplicate_record()
	return duplicate


## 执行 `require_initialized` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func _require_initialized() -> DomainResult:
	return DomainResult.ok() if _initialized else DomainResult.failure(
		&"persistence.repository_not_initialized", "repository must be initialized first"
	)
