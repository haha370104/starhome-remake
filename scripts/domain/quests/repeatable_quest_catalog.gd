class_name RepeatableQuestCatalog
extends RefCounted

const CONFIG_PATH := "res://data/gameplay/quests/repeatable_tasks_v1.json"
var providers: Dictionary = {}
var definitions: Dictionary = {}


## 加载配置并校验所有需求、里程碑物品和发布者引用；无效配置阻止服务启动。
func initialize(items: ItemCatalog) -> DomainResult:
	var loaded := JsonConfigLoader.load_dictionary(CONFIG_PATH)
	if not loaded.is_ok:
		return loaded
	providers = loaded.value.get("providers", {}).duplicate(true)
	definitions.clear()
	for entry: Dictionary in loaded.value.get("tasks", []):
		var task_id := String(entry.get("id", ""))
		if task_id.is_empty() or definitions.has(task_id) or not providers.has(entry.get("provider_id", "")):
			return DomainResult.failure(&"quest.invalid_config", "任务标识或发布者无效")
		if int(entry.get("maximum_completions", 0)) <= 0:
			return DomainResult.failure(&"quest.invalid_config", "任务次数必须为正整数")
		var item_entries: Array = entry.get("requirements", []).duplicate(true)
		for milestone: String in entry.get("milestone_rewards", {}):
			if not milestone.is_valid_int() or int(milestone) <= 0 or int(milestone) > int(entry["maximum_completions"]):
				return DomainResult.failure(&"quest.invalid_config", "奖励轮次超出任务上限")
			item_entries.append_array(rewards_at(entry, int(milestone)))
		for item: Dictionary in item_entries:
			if items.definition(String(item.get("definition_id", ""))).is_empty() or int(item.get("quantity", 0)) <= 0:
				return DomainResult.failure(&"quest.invalid_config", "任务引用了不存在的物品或无效数量")
		definitions[task_id] = entry.duplicate(true)
	return DomainResult.ok(self)


## 按发布者列出任务，保持 JSON 配置顺序。
func tasks_for(provider_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in definitions.values():
		if String(entry.get("provider_id", "")) == provider_id:
			result.append(entry.duplicate(true))
	return result


## 兼容单奖励对象及多奖励数组，支持护甲成对发放。
static func rewards_at(definition: Dictionary, completion: int) -> Array:
	var value: Variant = definition.get("milestone_rewards", {}).get(str(completion), [])
	return value.duplicate(true) if value is Array else [value.duplicate(true)] if value is Dictionary and not value.is_empty() else []
