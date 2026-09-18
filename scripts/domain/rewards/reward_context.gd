class_name RewardContext
extends RefCounted

var channel: StringName = &"experience"
var account_id := ""
var skill_id := ""
var item_id := ""
var species_id := ""
var source := ""
var population_kind: StringName = &"ordinary"
var now := 0
var food_status: FoodStatus


## 创建某玩家在一个权威时刻的奖励上下文，不读取客户端倍率字段。
## [param player] 已从权威记录还原的玩家聚合。
## [param timestamp] 本次结算的服务器 Unix 秒数。
## 返回携带账号与当前食品状态的临时上下文。
static func for_player(player: Player, timestamp: int) -> RewardContext:
	return for_account(player.account_id, player.food_status, timestamp)


## 用权威奖励事实建立上下文，允许技能成长无需还原玩家装备和仓库。
## [param account] 账号身份。[param food] 当前只读食品状态。[param timestamp] 服务端Unix秒数。
## 返回与完整Player入口相同的奖励上下文。
static func for_account(account: String, food: FoodStatus, timestamp: int) -> RewardContext:
	var context := RewardContext.new()
	context.account_id = account
	context.food_status = food
	context.now = timestamp
	return context


## 为一条掉落创建隔离的物品上下文，避免上一物品筛选条件泄漏。
## [param definition_id] 当前抽取的物品稳定标识。
## 返回共享只读食品状态但独立筛选字段的新上下文。
func for_item(definition_id: String) -> RewardContext:
	var result := RewardContext.new()
	result.channel = &"drop"
	result.account_id = account_id
	result.item_id = definition_id
	result.species_id = species_id
	result.source = source
	result.population_kind = population_kind
	result.now = now
	result.food_status = food_status
	return result
