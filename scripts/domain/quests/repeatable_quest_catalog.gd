class_name RepeatableQuestCatalog
extends RefCounted

const CONFIG_PATH := "res://data/gameplay/quests/repeatable_tasks_v1.json"
const TRAINING_CONFIG_PATH := "res://data/gameplay/quests/training_tasks_v1.json"
var providers: Dictionary = {}
var definitions: Dictionary = {}
var training_policy: Dictionary = {}
var training_targets: Array[Dictionary] = []


## 加载配置并校验所有需求、里程碑物品和发布者引用；无效配置阻止服务启动。
func initialize(items: ItemCatalog) -> DomainResult:
	var loaded := JsonConfigLoader.load_dictionary(CONFIG_PATH)
	if not loaded.is_ok:
		return loaded
	providers = loaded.value.get("providers", {}).duplicate(true)
	var training := JsonConfigLoader.load_dictionary(TRAINING_CONFIG_PATH)
	if not training.is_ok:
		return training
	providers.merge(training.value.get("providers", {}), true)
	training_policy = training.value.get("training_policy", {}).duplicate(true)
	var entries: Array = loaded.value.get("tasks", []).duplicate(true)
	entries.append_array(training.value.get("tasks", []))
	definitions.clear()
	for entry: Dictionary in entries:
		var task_id := String(entry.get("id", ""))
		if task_id.is_empty() or definitions.has(task_id) or not providers.has(entry.get("provider_id", "")):
			return DomainResult.failure(&"quest.invalid_config", "任务标识或发布者无效")
		var is_training := String(entry.get("kind", "collection")) == "kill_training"
		if not is_training and int(entry.get("maximum_completions", 0)) <= 0:
			return DomainResult.failure(&"quest.invalid_config", "任务次数必须为正整数")
		if is_training and (int(entry.get("daily_accept_limit", 0)) <= 0 or int(entry.get("kill_count", 0)) <= 0 \
				or String(entry.get("skill_id", "")) not in SkillBook.ORDERED_SKILLS or int(entry.get("skill_level_reward", 0)) != 1):
			return DomainResult.failure(&"quest.invalid_config", "训练任务技能、数量或奖励无效")
		var item_entries: Array = entry.get("requirements", []).duplicate(true)
		for milestone: String in entry.get("milestone_rewards", {}):
			if not milestone.is_valid_int() or int(milestone) <= 0 or int(milestone) > int(entry["maximum_completions"]):
				return DomainResult.failure(&"quest.invalid_config", "奖励轮次超出任务上限")
			item_entries.append_array(rewards_at(entry, int(milestone)))
		for item: Dictionary in item_entries:
			if items.definition(String(item.get("definition_id", ""))).is_empty() or int(item.get("quantity", 0)) <= 0:
				return DomainResult.failure(&"quest.invalid_config", "任务引用了不存在的物品或无效数量")
		definitions[task_id] = entry.duplicate(true)
	var targets_loaded := _load_training_targets()
	if not targets_loaded.is_ok:
		return targets_loaded
	return DomainResult.ok(self)


## 目标取自现有十级普通怪物分级且必须有启用刷怪配置，避免接到无处击杀的任务。
func _load_training_targets() -> DomainResult:
	training_targets.clear()
	var encounters := JsonConfigLoader.load_dictionary("res://data/gameplay/glory/glory_monster_encounters_v1.json")
	var monsters := JsonConfigLoader.load_dictionary("res://data/gameplay/glory/glory_monsters_v1.json")
	if not encounters.is_ok:
		return encounters
	if not monsters.is_ok:
		return monsters
	var locations: Dictionary = {}
	for encounter: Dictionary in encounters.value.get("encounters", []):
		if not bool(encounter.get("enabled", true)):
			continue
		for group: Dictionary in encounter.get("spawn_groups", []):
			if float(group.get("weight", 1.0)) <= 0.0:
				continue
			var species_id := String(group["monster_id"])
			if not locations.has(species_id):
				locations[species_id] = []
			locations[species_id].append(String(encounter["map_id"]))
	var names: Dictionary = {}
	for monster: Dictionary in monsters.value.get("definitions", []):
		names[String(monster["id"])] = String(monster["display_name"])
	var tiers: Dictionary = encounters.value.get("progression_tiers", {})
	for tier: String in tiers:
		for species_id: String in tiers[tier]:
			if names.has(species_id) and locations.has(species_id):
				training_targets.append({"species_id": species_id, "display_name": names[species_id],
					"tier": int(tier), "map_ids": locations[species_id].duplicate()})
	for band: Dictionary in training_policy.get("level_bands", []):
		var found := false
		for target: Dictionary in training_targets:
			for tier: Variant in band["tiers"]:
				found = found or int(target["tier"]) == int(tier)
		if not found:
			return DomainResult.failure(&"quest.no_targets", "训练等级区间没有已配置刷怪的候选怪物")
	return DomainResult.ok()


## 注入服务器时钟生成业务日期；默认按配置的北京时间零点换日。
func day_key(unix_seconds: int) -> String:
	return Time.get_date_string_from_unix_time(unix_seconds + int(training_policy.get("timezone_offset_seconds", 28800)))


## 创建纯领域训练规则。
func training_rule(definition: Dictionary) -> RepeatableTrainingTask:
	return RepeatableTrainingTask.new(definition, training_policy, training_targets)


## 统一任务日志和 NPC 窗口投影，避免把训练任务误当成零材料收集任务。
func snapshot(player: Player, definition: Dictionary, day: String) -> Dictionary:
	var state: Dictionary = player.quest_states.get(String(definition["id"]), {})
	if String(definition.get("kind", "")) == "kill_training":
		return training_rule(definition).snapshot(state, day)
	return RepeatableCollectionTask.new(definition).snapshot(player.inventory, state)


## 按发布者列出任务，保持 JSON 配置顺序。
func tasks_for(provider_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in definitions.values():
		if String(entry.get("provider_id", "")) == provider_id:
			result.append(entry.duplicate(true))
	return result


## 兼容单奖励对象及多奖励数组，支持护甲成对发放。
static func next_rewards(definition: Dictionary, completions: int) -> Array:
	var next := 2147483647
	for milestone: String in definition.get("milestone_rewards", {}):
		if int(milestone) > completions:
			next = mini(next, int(milestone))
	return rewards_at(definition, next)


## 返回指定轮次的全部额外物品奖励。
static func rewards_at(definition: Dictionary, completion: int) -> Array:
	var value: Variant = definition.get("milestone_rewards", {}).get(str(completion), [])
	return value.duplicate(true) if value is Array else [value.duplicate(true)] if value is Dictionary and not value.is_empty() else []
