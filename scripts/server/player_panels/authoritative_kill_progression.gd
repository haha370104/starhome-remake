class_name AuthoritativeKillProgression
extends RefCounted

var _quests: RepeatableQuestService
var _daily: DailyActivityService


## 共用已初始化规则，击杀结算不依赖商店命令或玩家记录映射。
## [param quests] 训练任务规则。[param daily] 日常活动规则。
func _init(quests: RepeatableQuestService, daily: DailyActivityService) -> void:
	_quests = quests
	_daily = daily


## 准备全部写集后一次提交，不复制历史账本，不在半完成状态发布通知。
## [param player] 唯一在线玩家。[param event] 战斗模块产生的死亡事实。
## 返回本次变化；重复或无关事实返回空值。
func apply(player: Player, event: Dictionary) -> PlayerChange:
	if String(event.get("killer_id", "")) != player.entity_id: return null
	var tasks := _quests.prepare_monster_kill(player, event)
	var daily := player.daily_activities.prepare_day(_daily.current_day(), _daily.catalog, player.level)
	player.daily_activities.prepare_kill(String(event.get("species_id", "")), String(event.get("death_id", "")), _daily.catalog, daily)
	var achievement := player.achievements.prepare(AchievementEvent.new(AchievementEvent.Kind.MONSTER_KILLED,
		String(event.get("species_id", "")), 1, String(event.get("death_id", ""))))
	if tasks.is_empty() and not daily.changed() and achievement.is_empty(): return null
	var previous_bonus := player.achievements.bonuses().to_dictionary() if not achievement.is_empty() else {}
	player.quest_states.merge(tasks, true)
	player.daily_activities.commit(daily)
	player.achievements.commit(achievement)
	var change := PlayerChange.new()
	for task_id: String in tasks:
		var row := _quests.catalog.snapshot(player, _quests.catalog.definitions[task_id], _quests.current_day())
		row["category"] = 0
		change.quests.append(row)
	if daily.changed(): change.daily = _daily.snapshot(player)
	if not achievement.is_empty():
		change.achievements[achievement.key] = achievement.count
		var bonus := player.achievements.bonuses()
		change.attributes_changed = previous_bonus != bonus.to_dictionary()
		if change.attributes_changed:
			player.vehicle.achievement_bonuses = bonus
			player.vehicle.reconcile_loadout_state(false)
	return change
