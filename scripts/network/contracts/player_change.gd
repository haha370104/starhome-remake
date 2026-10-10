class_name PlayerChange
extends RefCounted

var sync_id := ""
var base_revision := -1
var revision := -1
var inventory_revision := -1
var items: Array[Dictionary] = []
var removed_items: Array[String] = []
var inventory_currency := -1
var food: Dictionary = {}
var character_health := -1
var character: Dictionary = {}
var vehicle: Dictionary = {}
var vehicle_stats: Dictionary = {}
var presets: Dictionary = {}
var preset_server_time := -1
var quests: Array[Dictionary] = []
var skills: Array[Dictionary] = []
var level := -1
var achievements: Dictionary = {}
var daily: Dictionary = {}
var attributes_changed := false


## 完整校验增量容器与字段，客户端随后准备并原子应用领域状态。
## [param raw] 不可信传输字典。
## 返回类型化变更或格式错误。
static func parse(raw: Dictionary) -> DomainResult:
	if not raw.get("sync_id") is String or raw.sync_id.is_empty(): return _invalid()
	for key: String in ["base_revision", "transaction_revision"]:
		if not _count(raw.get(key)): return _invalid()
	var change := PlayerChange.new()
	change.sync_id = raw.sync_id
	change.base_revision = int(raw.base_revision)
	change.revision = int(raw.transaction_revision)
	if change.revision <= change.base_revision: return _invalid()
	for key: String in ["items", "mission_journal", "skills"]:
		if not raw.get(key, []) is Array: return _invalid()
	var seen: Dictionary = {}
	for row: Variant in raw.get("items", []):
		if not row is Dictionary or not row.get("instance_id") is String or row.instance_id.is_empty() \
			or not row.get("definition_id") is String or not _count(row.get("amount")) or row.amount <= 0 or seen.has(row.instance_id): return _invalid()
		var position: Variant = row.get("position_px")
		if not position is Array or position.size() != 2 or not _count(position[0]) or not _count(position[1]): return _invalid()
		seen[row.instance_id] = true
		change.items.append(row.duplicate(true))
	if not raw.get("removed_items", []) is Array: return _invalid()
	for identity: Variant in raw.get("removed_items", []):
		if not identity is String or identity.is_empty() or seen.has(identity): return _invalid()
		seen[identity] = true
		change.removed_items.append(identity)
	if raw.has("inventory_revision"):
		if not _count(raw.get("inventory_revision")): return _invalid()
		change.inventory_revision = int(raw.inventory_revision)
	elif not change.items.is_empty() or not change.removed_items.is_empty(): return _invalid()
	if raw.has("inventory_currency"):
		if change.inventory_revision < 0 or not _count(raw.inventory_currency): return _invalid()
		change.inventory_currency = int(raw.inventory_currency)
	if raw.has("food_status"):
		if not FoodStatus.valid_state(raw.food_status): return _invalid()
		change.food = raw.food_status.duplicate(true)
	if raw.has("character_health"):
		if not _count(raw.character_health): return _invalid()
		change.character_health = int(raw.character_health)
	for key: String in ["character", "vehicle", "vehicle_stats"]:
		if not raw.get(key, {}) is Dictionary: return _invalid()
	change.character = raw.get("character", {}).duplicate(true)
	if not change.character.is_empty():
		if not change.character.get("character_id") is String or not change.character.get("worn_items") is Array \
			or not change.character.get("skills") is Array: return _invalid()
		for key: String in ["health", "max_health", "level"]:
			if not _count(change.character.get(key)): return _invalid()
		if change.character.level < 10 or change.character.max_health < 1 or change.character.health > change.character.max_health: return _invalid()
	change.vehicle = raw.get("vehicle", {}).duplicate(true)
	change.vehicle_stats = raw.get("vehicle_stats", {}).duplicate(true)
	if raw.has("vehicle_presets"):
		if not raw.vehicle_presets is Dictionary or not VehicleLoadoutPresets.restore(raw.vehicle_presets).is_ok \
			or not _count(raw.get("preset_server_time")): return _invalid()
		change.presets = raw.vehicle_presets.duplicate(true)
		change.preset_server_time = int(raw.preset_server_time)
	seen.clear()
	for row: Variant in raw.get("mission_journal", []):
		if not row is Dictionary or not row.get("task_id") is String or row.task_id.is_empty() or seen.has(row.task_id): return _invalid()
		if not row.get("title") is String or not row.get("requirements", []) is Array: return _invalid()
		if row.get("kind", "") != "kill_training" and (not _count(row.get("completions")) or not _count(row.get("maximum_completions"))): return _invalid()
		for requirement: Variant in row.get("requirements", []):
			if not requirement is Dictionary or not requirement.get("display_name") is String or not _count(requirement.get("owned")) or not _count(requirement.get("required")): return _invalid()
		seen[row.task_id] = true
		change.quests.append(row.duplicate(true))
	seen.clear()
	for row: Variant in raw.get("skills", []):
		if not row is Dictionary or not row.get("id") is String or row.id not in SkillBook.ORDERED_SKILLS or seen.has(row.id): return _invalid()
		for key: String in ["base_level", "experience"]:
			if not _count(row.get(key)): return _invalid()
		var fraction: Variant = row.get("fractional_experience")
		if not (fraction is float or fraction is int) or not is_finite(float(fraction)) or fraction < 0 or fraction >= 1: return _invalid()
		seen[row.id] = true
		change.skills.append(row.duplicate(true))
	if raw.has("level"):
		if not _count(raw.level) or raw.level < 10: return _invalid()
		change.level = int(raw.level)
	if not raw.get("achievement_counters", {}) is Dictionary: return _invalid()
	change.achievements = raw.get("achievement_counters", {}).duplicate(true)
	if not PlayerAchievements.valid_state({"counters": change.achievements}): return _invalid()
	if not raw.get("daily_activities", {}) is Dictionary: return _invalid()
	change.daily = raw.get("daily_activities", {}).duplicate(true)
	if not change.daily.is_empty():
		if not change.daily.get("day") is String: return _invalid()
		for key: String in ["revision", "accepted_today", "completed_today", "points", "amethyst", "daily_limit", "completion_limit", "active_limit"]:
			if not _count(change.daily.get(key)): return _invalid()
		for key: String in ["offers", "active", "experience"]:
			if not change.daily.get(key) is Array: return _invalid()
			for row: Variant in change.daily[key]:
				if not row is Dictionary or not row.get("id") is String: return _invalid()
				if key != "offers" and not _count(row.get("progress")): return _invalid()
				for field: String in ["title", "description"]:
					if not row.get(field) is String: return _invalid()
				if not _count(row.get("reward")): return _invalid()
				if key == "experience":
					if not row.get("enabled") is bool or not _count(row.get("limit")) or not _count(row.get("claimed")) or not row.get("unavailable_reason") is String: return _invalid()
				else:
					if not _count(row.get("grade")) or row.grade < 1 or row.grade > 8 or not _count(row.get("quantity")) or not row.get("locations") is Array: return _invalid()
					if key == "active" and (not row.get("ticket") is String or not row.get("ready") is bool or not _count(row.get("kind"))): return _invalid()
	if not raw.get("attributes_changed", false) is bool: return _invalid()
	change.attributes_changed = raw.get("attributes_changed", false)
	return DomainResult.ok(change)


## 合并同一发布周期的最终值；只合并通知，不重算领域结算。
## [param later] 同一玩家较新的变化。
func merge(later: PlayerChange) -> void:
	revision = maxi(revision, later.revision)
	if later.inventory_revision >= 0: inventory_revision = later.inventory_revision
	if later.inventory_currency >= 0: inventory_currency = later.inventory_currency
	for identity: String in later.removed_items:
		items = items.filter(func(row: Dictionary) -> bool: return row.instance_id != identity)
		if identity not in removed_items: removed_items.append(identity)
	for row: Dictionary in later.items: removed_items.erase(String(row.instance_id))
	_merge_rows(items, later.items, "instance_id")
	if not later.food.is_empty(): food = later.food
	if later.character_health >= 0: character_health = later.character_health
	if not later.character.is_empty(): character = later.character
	if not later.vehicle.is_empty(): vehicle = later.vehicle
	if later.attributes_changed or not later.vehicle_stats.is_empty(): vehicle_stats = later.vehicle_stats
	if not later.presets.is_empty():
		presets = later.presets
		preset_server_time = later.preset_server_time
	_merge_rows(quests, later.quests, "task_id")
	_merge_rows(skills, later.skills, "id")
	achievements.merge(later.achievements, true)
	if later.level >= 0: level = later.level
	if not later.daily.is_empty(): daily = later.daily
	attributes_changed = attributes_changed or later.attributes_changed


## 按稳定身份保留每条记录的最后状态。
## [param target] 当前行集合。[param rows] 后续行。[param key] 身份字段。
static func _merge_rows(target: Array[Dictionary], rows: Array[Dictionary], key: String) -> void:
	for row: Dictionary in rows:
		var found := false
		for index in target.size():
			if target[index][key] == row[key]:
				target[index] = row
				found = true
				break
		if not found: target.append(row)


## 转为传输值，不包含可变领域对象和去重历史。
## 返回本次涉及的组件及同步版本。
func to_dictionary() -> Dictionary:
	var raw := {"sync_id": sync_id, "base_revision": base_revision, "transaction_revision": revision}
	if inventory_revision >= 0: raw["inventory_revision"] = inventory_revision
	if not items.is_empty(): raw["items"] = items
	if not removed_items.is_empty(): raw["removed_items"] = removed_items
	if inventory_currency >= 0: raw["inventory_currency"] = inventory_currency
	if not food.is_empty(): raw["food_status"] = food
	if character_health >= 0: raw["character_health"] = character_health
	if not character.is_empty(): raw["character"] = character
	if not vehicle.is_empty(): raw["vehicle"] = vehicle
	if not vehicle_stats.is_empty(): raw["vehicle_stats"] = vehicle_stats
	if not presets.is_empty(): raw.merge({"vehicle_presets": presets, "preset_server_time": preset_server_time})
	if not quests.is_empty(): raw["mission_journal"] = quests
	if not skills.is_empty(): raw["skills"] = skills
	if level >= 0: raw["level"] = level
	if not achievements.is_empty(): raw["achievement_counters"] = achievements
	if not daily.is_empty(): raw["daily_activities"] = daily
	if attributes_changed: raw["attributes_changed"] = true
	return raw


## 判断传输数值是否为有限非负整数。
## [param value] JSON 或本机传输中的数值。
## 返回是否满足计数约束。
static func _count(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and float(value) == floorf(float(value))


## 统一拒绝不完整的玩家增量。
## 返回格式错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"player.change_invalid", "invalid player change")
