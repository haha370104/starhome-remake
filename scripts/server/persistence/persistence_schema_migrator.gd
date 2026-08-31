class_name PersistenceSchemaMigrator
extends RefCounted

const CURRENT_SCHEMA_VERSION := 2


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
			1:
				var migrated := _migrate_one_to_two(working)
				if not migrated.is_ok:
					return migrated
				working = migrated.value
				version = 2
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


## 把仅保存整数技能等级的一版存档升级为完整技能成长状态。
## [param document] schema_version 为 1 的玩家存档根对象。
## 返回 schema_version 为 2、每项技能均含等级和经验余量的存档对象。
## 设计：迁移只补齐可确定的零经验，不臆造旧客户端从未保存的成长进度。
static func _migrate_one_to_two(document: Dictionary) -> DomainResult:
	var raw_players: Variant = document.get("players", {})
	if not raw_players is Dictionary:
		return DomainResult.failure(&"persistence.invalid_database", "schema-one players must be a dictionary")
	var players: Dictionary = raw_players.duplicate(true)
	for raw_character_id: Variant in players:
		var player: Variant = players[raw_character_id]
		if not player is Dictionary:
			return DomainResult.failure(&"persistence.invalid_database", "schema-one player must be a dictionary")
		var skills_value: Variant = player.get("character_skills", {})
		if not skills_value is Dictionary:
			return DomainResult.failure(&"persistence.invalid_database", "schema-one skills must be a dictionary")
		var migrated_skills: Dictionary = {}
		for raw_skill_id: Variant in skills_value:
			var raw_state: Variant = skills_value[raw_skill_id]
			migrated_skills[String(raw_skill_id)] = raw_state.duplicate(true) if raw_state is Dictionary else {
				"level": maxi(0, int(raw_state)),
				"current_exp": 0,
				"fractional_exp": 0.0,
			}
		player["character_skills"] = migrated_skills
		player["character_level"] = maxi(10, int(player.get("character_level", 10)))
		player["schema_version"] = 2
		players[raw_character_id] = player
	return DomainResult.ok({
		"schema_version": 2,
		"players": players,
		"migration_history": [1, 2],
	})
