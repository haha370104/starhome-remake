class_name EnhancementMonsterRules
extends RefCounted

var mutant_parents: Dictionary[String, String] = {}
var bosses := PackedStringArray()
var _drops: Dictionary[String, DropTable] = {}
var _unresponsive := PackedStringArray()
var _health_multiplier := 15
var _attack_multiplier := 3
var _defense_multiplier := 3
var _mutant_per_parent := 2
var _mutant_interval := 600
var _boss_per_map := 2
var _boss_interval := 1800


## 把新增怪物配置边界转换为类型化关系、配额及掉落表。
## [param raw] 原始JSON目录。
## 返回可应用的配置对象或首个格式错误。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	if int(raw.get("schema_version", 0)) != 1 or not raw.get("mutant_parents") is Dictionary \
		or not raw.get("boss_species") is Array or not raw.get("definitions") is Array:
		return DomainResult.failure(&"enhancement.monster_rules", "强化怪物目录格式错误")
	var rules := EnhancementMonsterRules.new()
	for id: String in raw.mutant_parents:
		rules.mutant_parents[id] = String(raw.mutant_parents[id])
	rules.bosses = PackedStringArray(raw.boss_species)
	var seen_bosses: Dictionary[String, bool] = {}
	for id: String in rules.bosses:
		if id.is_empty() or seen_bosses.has(id) or rules.mutant_parents.has(id):
			return DomainResult.failure(&"enhancement.monster_rules", "BOSS身份为空、重复或与变异冲突")
		seen_bosses[id] = true
	if rules.bosses.is_empty():
		return DomainResult.failure(&"enhancement.monster_rules", "BOSS物种池不能为空")
	rules._unresponsive = PackedStringArray(raw.get("unresponsive_species", []))
	rules._health_multiplier = int(raw.get("health_multiplier", 0))
	rules._attack_multiplier = int(raw.get("attack_multiplier", 0))
	rules._defense_multiplier = int(raw.get("defense_multiplier", 0))
	rules._mutant_per_parent = int(raw.get("mutant_per_parent", 0))
	rules._mutant_interval = int(raw.get("mutant_interval_seconds", 0))
	rules._boss_per_map = int(raw.get("boss_per_map", 0))
	rules._boss_interval = int(raw.get("boss_interval_seconds", 0))
	for value: int in [rules._health_multiplier, rules._attack_multiplier, rules._defense_multiplier,
		rules._mutant_per_parent, rules._mutant_interval, rules._boss_per_map, rules._boss_interval]:
		if value <= 0:
			return DomainResult.failure(&"enhancement.monster_rules", "怪物倍率和刷新配额须为正数")
	for row: Dictionary in raw.definitions:
		var id := String(row.get("monster_id", ""))
		if id.is_empty() or rules._drops.has(id):
			return DomainResult.failure(&"enhancement.monster_rules", "怪物掉落身份重复或为空")
		var table := DropTable.new()
		var checked := table.configure(row.get("drops"))
		if not checked.is_ok or not table.is_configured():
			return DomainResult.failure(&"enhancement.monster_rules", "新增怪物须有有效强化掉落表")
		rules._drops[id] = table
	return DomainResult.ok(rules)


## 在正式目录组装边界派生本体倍率并追加新增掉落，不覆盖原有材料。
## [param species] 现有怪物定义索引，已包含新手覆盖和原版掉落。
## [param encounters] 现有地图种群索引，已包含D04覆盖。
## 返回全部来源关系通过验证后的应用结果。
func apply(species: Dictionary, encounters: Dictionary) -> DomainResult:
	var affected := PackedStringArray(mutant_parents.keys())
	affected.append_array(bosses)
	for id: String in affected:
		if not species.has(id) or not _drops.has(id) or (mutant_parents.has(id) and not species.has(mutant_parents[id])):
			return DomainResult.failure(&"enhancement.monster_source", "变异、BOSS或本体来源未登记")
	for id: String in affected:
		var monster: Dictionary = species[id]
		if mutant_parents.has(id):
			var parent: Dictionary = species[mutant_parents[id]]
			monster.stats.max_health = int(parent.stats.max_health) * _health_multiplier
			monster.stats.base_attack = int(parent.stats.base_attack) * _attack_multiplier
			# 原服防御未知仍保留null；运行防御单列，确立本体三倍关系。
			monster.combat["runtime_defense"] = int(parent.combat.get("runtime_defense", 0)) * _defense_multiplier
			monster["remake_parent_id"] = mutant_parents[id]
		monster.combat.engagement_policy = "unresponsive" if id in _unresponsive else "retaliatory"
		var existing: Array = monster.drops.duplicate(true) if monster.get("drops") is Array else []
		existing.append_array(_drops[id].entries())
		monster.drops = existing
	var map_ids := encounters.keys()
	map_ids.sort()
	var boss_map_index := 0
	for map_id: String in map_ids:
		var encounter: Dictionary = encounters[map_id]
		if not bool(encounter.get("enabled", false)):
			continue
		var groups: Array[Dictionary] = []
		for base: Dictionary in encounter.get("spawn_groups", []):
			for mutant: String in mutant_parents:
				if mutant_parents[mutant] == String(base.monster_id):
					groups.append({"monster_id": mutant, "weight": 1.0})
		if not groups.is_empty():
			encounter["mutant_spawn_groups"] = groups
			encounter["mutant_population_policy"] = {"maximum_population": groups.size() * _mutant_per_parent,
				"replenish_interval_seconds": _mutant_interval}
		if int(encounter.get("progression", {}).get("danger_tier", 0)) == 10:
			var boss_groups: Array[Dictionary] = []
			for index: int in range(_boss_per_map):
				boss_groups.append({"monster_id": bosses[(boss_map_index * _boss_per_map + index) % bosses.size()], "weight": 1.0})
			encounter["boss_spawn_groups"] = boss_groups
			encounter["boss_population_policy"] = {"maximum_population": _boss_per_map, "replenish_interval_seconds": _boss_interval}
			boss_map_index += 1
	return DomainResult.ok()
