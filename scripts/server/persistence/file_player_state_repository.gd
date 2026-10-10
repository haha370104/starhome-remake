class_name FilePlayerStateRepository
extends PlayerStateRepository

const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")
const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")
const CURRENT_SCHEMA_VERSION := 4

var database_path := ""
var _schema_version := 0
var _players: Dictionary = {}
var _initialized := false
var _writer: BackgroundFileWriter
var _durable_commit := false


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
		raw_document = {"schema_version": CURRENT_SCHEMA_VERSION, "players": {},
			"ground_cleanup_at": ground_cleanup_at, "ground_items": {}}
	if int(raw_document.get("schema_version", -1)) != CURRENT_SCHEMA_VERSION:
		return DomainResult.failure(&"persistence.unsupported_schema", "persistence schema version is unsupported")
	var cleanup_at: Variant = raw_document.get("ground_cleanup_at")
	if raw_document.size() != 4 or not raw_document.has("players") \
		or not raw_document.get("ground_items") is Dictionary \
		or not (cleanup_at is int or cleanup_at is float) or not is_finite(float(cleanup_at)) \
		or cleanup_at != floorf(float(cleanup_at)) or cleanup_at <= 0 or cleanup_at > 9007199254740991:
		return DomainResult.failure(&"persistence.invalid_database", "persistence root fields are invalid")
	var loaded_players_result := _decode_players(raw_document["players"])
	if not loaded_players_result.is_ok:
		return loaded_players_result
	var ground_result := _validate_ground_items(raw_document.ground_items, loaded_players_result.value)
	if not ground_result.is_ok: return ground_result
	ground_cleanup_at = ceili(float(raw_document.ground_cleanup_at) / GROUND_CLEAR_INTERVAL) * GROUND_CLEAR_INTERVAL
	ground_items = raw_document.ground_items
	if int(Time.get_unix_time_from_system()) >= ground_cleanup_at:
		ground_items = {}
		ground_cleanup_at = (floori(Time.get_unix_time_from_system() / GROUND_CLEAR_INTERVAL) + 1) * GROUND_CLEAR_INTERVAL
	var persist_result := _persist_document(_encode_document(loaded_players_result.value))
	if not persist_result.is_ok:
		return persist_result
	_schema_version = CURRENT_SCHEMA_VERSION
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
	return _commit_candidate(candidate, state.character_id, true)


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


## 返回精确昵称匹配的角色标识，不返回角色存档内容。
func find_player_ids_by_display_name(display_name: String) -> Array[String]:
	if not _initialized or display_name.is_empty():
		return []
	var matches: Array[String] = []
	for character_id: String in _players:
		if String((_players[character_id] as PlayerStateRecord).display_name) == display_name:
			matches.append(character_id)
	return matches


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
	var candidate_state := state.shallow_copy()
	candidate_state.revision = expected_revision + 1
	var validation := candidate_state.validate()
	if not validation.is_ok:
		return validation
	var candidate := _duplicate_player_index(_players)
	candidate[state.character_id] = candidate_state
	return _commit_candidate(candidate, state.character_id)


func save_players_atomic(states: Dictionary, expected_revisions: Dictionary) -> DomainResult:
	var ready := _require_initialized()
	if not ready.is_ok: return ready
	if states.is_empty() or states.size() != expected_revisions.size():
		return DomainResult.failure(&"persistence.invalid_transaction", "atomic player save requires matching nonempty inputs")
	var candidate := _duplicate_player_index(_players)
	var identities: Array[String] = []
	for raw_identity: Variant in states:
		if not raw_identity is String or not expected_revisions.has(raw_identity):
			return DomainResult.failure(&"persistence.invalid_transaction", "atomic player save identities are invalid")
		var identity := String(raw_identity)
		var state: Variant = states[identity]
		var expected_value: Variant = expected_revisions[identity]
		if not state is PlayerStateRecord or state.character_id != identity \
				or not expected_value is int or int(expected_value) < 0:
			return DomainResult.failure(&"persistence.invalid_transaction", "atomic player save record is invalid")
		if not _players.has(identity):
			return DomainResult.failure(&"persistence.character_not_found", "character does not exist")
		var persisted: PlayerStateRecord = _players[identity]
		if persisted.revision != int(expected_value):
			return DomainResult.failure(&"persistence.revision_conflict", "player state revision changed")
		var candidate_state: PlayerStateRecord = state.shallow_copy()
		candidate_state.revision = int(expected_value) + 1
		var validation := candidate_state.validate()
		if not validation.is_ok: return validation
		candidate[identity] = candidate_state
		identities.append(identity)
	var committed := _commit_candidate(candidate, identities[0])
	if not committed.is_ok: return committed
	var records: Dictionary = {}
	for identity: String in identities:
		records[identity] = (_players[identity] as PlayerStateRecord).shallow_copy()
	return DomainResult.ok(records)


## 多角色原子保存，并在成功返回前等待后台快照落盘。
func save_players_atomic_durable(states: Dictionary, expected_revisions: Dictionary) -> DomainResult:
	var previous := _durable_commit
	_durable_commit = true
	var result := save_players_atomic(states, expected_revisions)
	_durable_commit = previous
	return result


func save_ground_transfer(state: PlayerStateRecord, expected_revision: int, transfer: Dictionary) -> DomainResult:
	var previous := ground_items
	ground_items = ground_items.duplicate()
	var items: Dictionary = ground_items.get(transfer.map_id, {}).duplicate()
	if transfer.item.is_empty(): items.erase(transfer.loot_id)
	else: items[transfer.loot_id] = transfer.item
	if items.is_empty(): ground_items.erase(transfer.map_id)
	else: ground_items[transfer.map_id] = items
	var saved := save_player(state, expected_revision)
	if not saved.is_ok: ground_items = previous
	else: ground_dirty = true
	return saved


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
func _commit_candidate(
	candidate: Dictionary,
	committed_character_id: String,
	return_deep_copy := false,
) -> DomainResult:
	if _writer == null or _durable_commit:
		var materialize_started_at := PerformanceTelemetryScript.begin(&"autosave_durable_snapshot_materialize")
		var document := _encode_document(candidate)
		PerformanceTelemetryScript.end(&"autosave_durable_snapshot_materialize", materialize_started_at)
		var persisted := _persist_document(document)
		if not persisted.is_ok: return persisted
	_players = candidate
	var committed: PlayerStateRecord = _players[committed_character_id]
	return DomainResult.ok(committed.duplicate_record() if return_deep_copy else committed.shallow_copy())


## 执行 `persist_document` 对应的模块操作。
## [param document] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _persist_document(document: Dictionary) -> DomainResult:
	if _writer == null:
		var sync_write_started_at := PerformanceTelemetryScript.begin(&"autosave_durable_sync_write")
		var sync_result := AtomicJsonFile.write_document(_native_storage_path(), document)
		PerformanceTelemetryScript.end(&"autosave_durable_sync_write", sync_write_started_at)
		return sync_result
	var enqueue_started_at := PerformanceTelemetryScript.begin(&"autosave_durable_enqueue")
	if _writer.enqueue_snapshot(_native_storage_path(), document, true) != OK:
		PerformanceTelemetryScript.end(&"autosave_durable_enqueue", enqueue_started_at)
		return DomainResult.failure(&"persistence.storage_error", "background snapshot queue is closed")
	PerformanceTelemetryScript.end(&"autosave_durable_enqueue", enqueue_started_at)
	var wait_started_at := PerformanceTelemetryScript.begin(&"autosave_durable_flush_wait")
	var result := _writer.flush()
	PerformanceTelemetryScript.end(&"autosave_durable_flush_wait", wait_started_at)
	return result


## 为实际游戏启用延迟持久化，事务仍在内存中原子校验并递增版本。
## 返回后台线程启动结果；直接使用文件仓储的工具仍可保留同步模式。
func enable_background_writes() -> DomainResult:
	if _writer != null: return DomainResult.ok()
	_writer = BackgroundFileWriter.new()
	if _writer.start() != OK:
		_writer = null
		return DomainResult.failure(&"persistence.storage_error", "cannot start persistence worker")
	return DomainResult.ok()


## 正常退出专用：后台写盘完成后才采用候选，失败保持当前内存事务不变。
## [param state] 已采集的退出候选。[param expected_revision] 当前内存版本。
## 返回已写盘的角色或失败；普通装备、掉落事务不等待此接口。
func save_player_durable(state: PlayerStateRecord, expected_revision: int) -> DomainResult:
	_durable_commit = true
	var result := save_player(state, expected_revision)
	_durable_commit = false
	return result


## 在检查点时将最新内存索引交给后台，覆盖队列中尚未执行的旧快照。
## 返回入队状态，并报告上次后台失败；下一次检查点仍会重试最新状态。
func queue_checkpoint() -> DomainResult:
	if _writer == null:
		var saved := _persist_document(_encode_document(_players))
		if saved.is_ok: ground_dirty = false
		return saved
	var previous := _writer.last_result()
	var encode_started_at := PerformanceTelemetryScript.begin(&"autosave_snapshot_materialize")
	var document := _encode_document(_players)
	PerformanceTelemetryScript.end(&"autosave_snapshot_materialize", encode_started_at)
	if _writer.enqueue_snapshot(_native_storage_path(), document, true) != OK:
		return DomainResult.failure(&"persistence.storage_error", "background snapshot queue is closed")
	ground_dirty = false
	return previous


## 等待最新内存快照落盘；只用于退出或显式保存，不在普通游戏事务中调用。
## 返回实际写盘结果。
func flush() -> DomainResult:
	if _writer == null:
		return queue_checkpoint() if ground_dirty else DomainResult.ok()
	var encode_started_at := PerformanceTelemetryScript.begin(&"autosave_snapshot_materialize")
	var document := _encode_document(_players)
	PerformanceTelemetryScript.end(&"autosave_snapshot_materialize", encode_started_at)
	return _persist_document(document)


## 查询后台线程最近一次完成结果，不等待或触发新写盘。
func checkpoint_status() -> DomainResult:
	return _writer.last_result() if _writer != null else DomainResult.ok()


## 正常释放仓储时保存内存中最后版本并回收文件线程。
## 返回最终写盘结果，重复关闭安全。
func close() -> DomainResult:
	if _writer == null: return DomainResult.ok()
	var result := flush()
	_writer.close()
	_writer = null
	return result


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
		"schema_version": CURRENT_SCHEMA_VERSION,
		"players": serialized,
		"ground_cleanup_at": ground_cleanup_at,
		"ground_items": ground_items.duplicate(true),
	}


func _validate_ground_items(maps: Dictionary, players: Dictionary) -> DomainResult:
	var identities: Dictionary = {}
	var loot_ids: Dictionary = {}
	for player: PlayerStateRecord in players.values():
		for stack: InventoryStackRecord in player.inventory_stacks: identities[stack.stack_id] = true
		for slot: EquipmentSlotRecord in player.equipment_slots: identities[slot.item_instance_id] = true
		for cabinet: Array in player.warehouse.to_dictionary().cabinets:
			for stack: Dictionary in cabinet: identities[stack.stack_id] = true
	for map_id: Variant in maps:
		if not map_id is String or map_id.is_empty() or not maps[map_id] is Dictionary:
			return DomainResult.failure(&"persistence.invalid_ground_items", "invalid ground map")
		for loot_id: Variant in maps[map_id]:
			var entry: Variant = maps[map_id][loot_id]
			if not loot_id is String or loot_id.is_empty() or loot_ids.has(loot_id) or not entry is Dictionary \
				or entry.size() != 2 or not entry.get("position") is Array or entry.position.size() != 2:
				return DomainResult.failure(&"persistence.invalid_ground_items", "invalid ground item")
			for coordinate: Variant in entry.position:
				if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
					return DomainResult.failure(&"persistence.invalid_ground_items", "invalid ground position")
			var record := InventoryStackRecord.from_dictionary(entry.get("item"))
			if not record.is_ok: return record
			if identities.has(record.value.stack_id):
				return DomainResult.failure(&"persistence.duplicate_ground_item", "ground item is also held by a player or another map")
			identities[record.value.stack_id] = true
			loot_ids[loot_id] = true
	return DomainResult.ok()


## 复制索引以原子替换单个角色；记录只在保存时复制，对外读取另返回副本。
## [param source] 当前已提交的角色索引。
## 返回保留旧记录引用的独立索引。
func _duplicate_player_index(source: Dictionary) -> Dictionary:
	return source.duplicate()


## 执行 `require_initialized` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func _require_initialized() -> DomainResult:
	return DomainResult.ok() if _initialized else DomainResult.failure(
		&"persistence.repository_not_initialized", "repository must be initialized first"
	)
