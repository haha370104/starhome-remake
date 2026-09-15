class_name DailyActivityService
extends RefCounted

const COMMANDS := ["query_daily_activities", "accept_mercenary", "abandon_mercenary", "complete_mercenary", "claim_experience"]
var catalog := DailyActivityCatalog.new()
var clock := Callable()


## 初始化与商城共享物品身份的日常目录。
## [param items] 已加载的权威物品目录。
## 返回目录初始化结果。
func initialize(items: ItemCatalog) -> DomainResult:
	return catalog.initialize(items)


## 以注入时钟或服务器时间计算北京时间业务日，忽略客户端日期。
## 返回用于换日与每日限额的日期。
func current_day() -> String:
	var seconds := int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())
	return Time.get_date_string_from_unix_time(seconds + int(catalog.policy.timezone_offset))


## 调用玩家内部任务行为，外层 commerce 服务负责候选存档原子提交。
## [param player] 当前隔离的玩家聚合。
## [param command] 不可信的客户端意图。
## 返回业务结果，失败时外层丢弃整个候选聚合。
func execute(player: Player, command: Dictionary) -> DomainResult:
	player.daily_activities.prepare(current_day(), catalog, player.level)
	var revision := int(command.get("daily_revision", -1))
	match String(command.type):
		"query_daily_activities":
			return DomainResult.ok({"action": "daily_query"})
		"accept_mercenary":
			return player.daily_activities.accept(String(command.get("task_id", "")), revision, catalog, player.level)
		"abandon_mercenary":
			return player.daily_activities.abandon(String(command.get("ticket", "")), revision)
		"complete_mercenary", "claim_experience":
			return player.claim_daily_reward(command, catalog)
	return DomainResult.failure(&"daily.unknown_command", "未知日常任务操作")


## 接收权威怪物死亡事实，并在换日后推进仍有效的任务。
## [param player] 事件归属的隔离玩家聚合。
## [param event] 经过击杀归属验证的死亡事件。
## 返回是否改变可持久化状态。
func record_kill(player: Player, event: Dictionary) -> bool:
	var before := player.daily_activities.to_dictionary()
	player.daily_activities.prepare(current_day(), catalog, player.level)
	player.daily_activities.record_kill(String(event.get("species_id", "")), String(event.get("death_id", "")), catalog)
	return before != player.daily_activities.to_dictionary()


## 为窗口投影任务与钱包，不在查询投影时隐式换日或抽取。
## [param player] 当前玩家聚合。
## 返回日常窗口的只读状态。
func snapshot(player: Player) -> Dictionary:
	var result := player.daily_activities.snapshot(catalog, player.inventory)
	result["amethyst"] = player.amethyst.balance()
	result["daily_limit"] = catalog.policy.daily_limit
	result["completion_limit"] = catalog.policy.completion_limit
	result["active_limit"] = catalog.policy.active_limit
	return result
