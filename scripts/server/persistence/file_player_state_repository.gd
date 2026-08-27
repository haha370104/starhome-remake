class_name FilePlayerStateRepository
extends PlayerStateRepository

const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")
const Migrator := preload("res://scripts/server/persistence/persistence_schema_migrator.gd")

var database_path := ""
var _schema_version := 0
var _players: Dictionary = {}
var _initialized := false


## Configures the explicit development substitute at [param requested_database_path].
## [param requested_database_path] Writable JSON path; it is not an SQLite database.
## Design: This adapter exists for no-dependency tests and local recovery only, not production concurrency.
func _init(requested_database_path: String = "") -> void:
	database_path = requested_database_path


## Loads or creates the file store and applies deterministic document migrations.
## Returns success only after a migrated snapshot is durably materialized.
func initialize() -> DomainResult:
	if database_path.is_empty():
		return DomainResult.failure(&"persistence.invalid_database_path", "file repository path is empty")
	var recovered := _recover_interrupted_commit()
	if not recovered.is_ok:
		return recovered
	var raw_document: Dictionary
	if FileAccess.file_exists(database_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(database_path))
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


## Creates one new [param state] through an atomic whole-document commit.
## [param state] Validated player aggregate whose character ID must be unique.
## Returns committed revision-zero state or a conflict/storage failure.
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


## Loads the isolated aggregate identified by [param character_id].
## [param character_id] Existing stable character identity.
## Returns a defensive typed copy or a stable not-found failure.
func load_player(character_id: String) -> DomainResult:
	var ready := _require_initialized()
	if not ready.is_ok:
		return ready
	if not _players.has(character_id):
		return DomainResult.failure(&"persistence.character_not_found", "character does not exist")
	return DomainResult.ok((_players[character_id] as PlayerStateRecord).duplicate_record())


## Saves [param state] when persisted revision equals [param expected_revision].
## [param state] Complete aggregate candidate; repository owns the revision increment.
## [param expected_revision] Caller-observed aggregate revision.
## Returns an isolated committed state or a conflict/storage failure.
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


## Runs [param operation] against an isolated [param character_id] aggregate and commits once.
## [param character_id] Existing character loaded at its current revision.
## [param operation] Callable returning `DomainResult`; failures roll back every mutation.
## Returns committed state with one revision increment or the unmodified callback/storage failure.
## Design: Callback code never receives the repository-owned instance.
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


## Reports the materialized schema version.
## Returns zero before initialization or the applied version afterward.
func current_schema_version() -> int:
	return _schema_version


## Persists [param candidate] before publishing it as repository state.
## [param candidate] Fully isolated player index for the next database snapshot.
## [param committed_character_id] Character whose defensive committed copy is returned.
## Returns committed state or a storage error without changing `_players`.
func _commit_candidate(candidate: Dictionary, committed_character_id: String) -> DomainResult:
	var document := _encode_document(candidate)
	var persisted := _persist_document(document)
	if not persisted.is_ok:
		return persisted
	_players = candidate
	return DomainResult.ok((_players[committed_character_id] as PlayerStateRecord).duplicate_record())


## Writes [param document] with a recoverable temp/backup rename protocol.
## [param document] Complete JSON-compatible database snapshot.
## Returns success after replacement or a stable I/O failure.
## Design: This best-effort file protocol is a development substitute; SQLite must provide production ACID.
func _persist_document(document: Dictionary) -> DomainResult:
	var absolute_directory := ProjectSettings.globalize_path(database_path.get_base_dir())
	var make_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		return DomainResult.failure(&"persistence.storage_error", "cannot create database directory")
	var temporary_path := database_path + ".tmp"
	var backup_path := database_path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return DomainResult.failure(&"persistence.storage_error", "cannot open temporary database file")
	file.store_string(JSON.stringify(document, "  "))
	file.flush()
	file.close()
	var directory := DirAccess.open(database_path.get_base_dir())
	if directory == null:
		return DomainResult.failure(&"persistence.storage_error", "cannot open database directory")
	var database_name := database_path.get_file()
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


## Recovers a staged backup when a prior file replacement was interrupted.
## Returns success when the main file is present or restoration succeeds.
func _recover_interrupted_commit() -> DomainResult:
	var backup_path := database_path + ".bak"
	if FileAccess.file_exists(database_path) or not FileAccess.file_exists(backup_path):
		return DomainResult.ok()
	var directory := DirAccess.open(database_path.get_base_dir())
	if directory == null or directory.rename(backup_path.get_file(), database_path.get_file()) != OK:
		return DomainResult.failure(&"persistence.storage_error", "cannot recover staged database backup")
	return DomainResult.ok()


## Decodes typed player aggregates from persistence [param raw_players].
## [param raw_players] Schema-one dictionary keyed by character ID.
## Returns a typed index or the first aggregate validation failure.
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


## Serializes the complete typed [param players] index.
## [param players] Candidate aggregate dictionary owned by this repository.
## Returns a schema-one JSON-compatible database document.
func _encode_document(players: Dictionary) -> Dictionary:
	var serialized: Dictionary = {}
	for character_id: String in players:
		serialized[character_id] = (players[character_id] as PlayerStateRecord).to_dictionary()
	return {
		"schema_version": Migrator.CURRENT_SCHEMA_VERSION,
		"players": serialized,
		"migration_history": [1],
	}


## Creates isolated copies of every aggregate in [param source].
## [param source] Current or candidate player index.
## Returns a new dictionary with no shared player-state objects.
func _duplicate_player_index(source: Dictionary) -> Dictionary:
	var duplicate: Dictionary = {}
	for character_id: String in source:
		duplicate[character_id] = (source[character_id] as PlayerStateRecord).duplicate_record()
	return duplicate


## Rejects repository calls made before initialization.
## Returns success only when the backing snapshot was loaded and migrated.
func _require_initialized() -> DomainResult:
	return DomainResult.ok() if _initialized else DomainResult.failure(
		&"persistence.repository_not_initialized", "repository must be initialized first"
	)
