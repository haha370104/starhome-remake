class_name PersistenceSchemaMigrator
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const CURRENT_SCHEMA_VERSION := 1


## Migrates persistence [param document] through every supported version in order.
## [param document] JSON-compatible database root copied before any mutation.
## Returns a migrated copy or a stable unsupported/malformed schema failure.
## Design: Migrations are deterministic and never mutate the caller's document.
static func migrate_document(document: Dictionary) -> DomainResult:
	var working := document.duplicate(true)
	var version := int(working.get("schema_version", -1))
	if version < 0 or version > CURRENT_SCHEMA_VERSION:
		return DomainResult.failure(&"persistence.unsupported_schema", "persistence schema version is unsupported")
	while version < CURRENT_SCHEMA_VERSION:
		match version:
			0:
				var migrated := _migrate_zero_to_one(working)
				if not migrated.is_ok:
					return migrated
				working = migrated.value
				version = 1
			_:
				return DomainResult.failure(&"persistence.migration_missing", "no migration is registered for schema version")
	if not working.get("players") is Dictionary:
		return DomainResult.failure(&"persistence.invalid_database", "persistence root players must be a dictionary")
	return DomainResult.ok(working)


## Converts the legacy [param document] from schema zero to normalized schema one.
## [param document] Schema-zero root using the legacy `characters` aggregate key.
## Returns a new schema-one document or a validation failure.
static func _migrate_zero_to_one(document: Dictionary) -> DomainResult:
	var legacy_players: Variant = document.get("characters", {})
	if not legacy_players is Dictionary:
		return DomainResult.failure(&"persistence.invalid_database", "schema-zero characters must be a dictionary")
	return DomainResult.ok({
		"schema_version": 1,
		"players": legacy_players.duplicate(true),
		"migration_history": [1],
	})
