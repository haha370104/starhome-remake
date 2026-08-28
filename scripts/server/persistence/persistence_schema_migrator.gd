class_name PersistenceSchemaMigrator
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const CURRENT_SCHEMA_VERSION := 1


## 执行 `migrate_document` 对应的模块操作。
## [param document] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
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


## 执行 `migrate_zero_to_one` 对应的模块操作。
## [param document] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func _migrate_zero_to_one(document: Dictionary) -> DomainResult:
	var legacy_players: Variant = document.get("characters", {})
	if not legacy_players is Dictionary:
		return DomainResult.failure(&"persistence.invalid_database", "schema-zero characters must be a dictionary")
	return DomainResult.ok({
		"schema_version": 1,
		"players": legacy_players.duplicate(true),
		"migration_history": [1],
	})
