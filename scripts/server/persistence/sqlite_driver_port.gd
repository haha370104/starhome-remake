class_name SqliteDriverPort
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")


## Reports whether the concrete SQLite driver is ready for production calls.
## Returns false for this boundary-only base implementation.
func is_available() -> bool:
	return false


## Opens the SQLite database at [param database_path].
## [param database_path] Server-configured persistent database path.
## Returns success or a driver-specific stable failure.
func open_database(database_path: String) -> DomainResult:
	return DomainResult.failure(&"persistence.sqlite_driver_unavailable", "no SQLite driver is installed")


## Executes parameterized [param sql] with positional [param parameters].
## [param sql] Trusted repository-owned SQL statement.
## [param parameters] Values bound by the concrete driver, never interpolated.
## Returns affected-row metadata or a stable driver failure.
func execute(sql: String, parameters: Array = []) -> DomainResult:
	return DomainResult.failure(&"persistence.sqlite_driver_unavailable", "no SQLite driver is installed")


## Queries parameterized [param sql] with positional [param parameters].
## [param sql] Trusted repository-owned query.
## [param parameters] Values bound by the concrete driver, never interpolated.
## Returns result rows or a stable driver failure.
func query(sql: String, parameters: Array = []) -> DomainResult:
	return DomainResult.failure(&"persistence.sqlite_driver_unavailable", "no SQLite driver is installed")


## Starts one SQLite transaction using immediate writer locking.
## Returns success or a stable driver failure.
func begin_immediate() -> DomainResult:
	return execute("BEGIN IMMEDIATE")


## Commits the active SQLite transaction.
## Returns success or a stable driver failure.
func commit() -> DomainResult:
	return execute("COMMIT")


## Rolls back the active SQLite transaction.
## Returns success or a stable driver failure.
func rollback() -> DomainResult:
	return execute("ROLLBACK")


## Detects known SQLite extension classes and singletons in the current runtime.
## Returns diagnostic capability facts without claiming a usable driver adapter.
static func runtime_capability() -> Dictionary:
	var known_classes: Array[StringName] = []
	for candidate: StringName in [&"SQLite", &"SQLiteDatabase", &"SQLiteStatement", &"SQLite3"]:
		if ClassDB.class_exists(candidate):
			known_classes.append(candidate)
	return {
		"available": not known_classes.is_empty() or Engine.has_singleton("SQLite") or Engine.has_singleton("SQLite3"),
		"known_classes": known_classes,
		"known_singleton": Engine.has_singleton("SQLite") or Engine.has_singleton("SQLite3"),
		"adapter_status": &"driver_adapter_required",
	}
