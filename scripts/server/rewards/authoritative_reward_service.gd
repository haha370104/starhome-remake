class_name AuthoritativeRewardService
extends RefCounted

var pipeline: RewardPipeline
var _states: AuthoritativeAutosaveService
var _items: ItemCatalog


## 组装权威账号查询与只读倍率配置，不保存第二份玩家状态。
## [param states] 服务器当前玩家状态所有者。
## [param rewards] 可注入的受信任切面，省略时使用统一配置。
## 返回初始化结果；无效配置使服务端启动失败。
func initialize(states: AuthoritativeAutosaveService, rewards: RewardPipeline = null) -> DomainResult:
	_states = states
	var loaded: DomainResult = DomainResult.ok(rewards) if rewards != null else RewardPolicyLoader.load_default()
	if not loaded.is_ok:
		return loaded
	pipeline = loaded.value
	_items = ItemCatalog.new()
	return _items.initialize()


## 在怪物死亡时按击杀者的最新权威账号状态抽取，并按物品堆叠上限拆包。
## [param monster] 已确认死亡归属的怪物领域对象。
## [param killer_id] 权威攻击实体标识，不是客户端提供的账号ID。
## [param random] 地图战斗模块的随机源。
## [param now] 本次死亡的权威 Unix 秒数。
## 返回可生成地面实体的完整掉落；拾取时不再应用倍率。
func roll_monster_loot(monster: MonsterLifecycle, killer_id: String, random: RandomNumberGenerator, now: int) -> DomainResult:
	var context := RewardContext.new()
	context.channel = &"drop"
	context.now = now
	context.source = "monster_kill"
	context.species_id = monster.species_id
	context.population_kind = monster.population_kind
	var state := _states.state_for(killer_id) if _states != null else null
	if state != null:
		context.account_id = state.account_id
		context.food_status = FoodStatus.new(state.food_status)
	var rolled := monster.drop_table.roll_with_modifiers(random, pipeline, context)
	if not rolled.is_ok:
		return rolled
	var result: Array[Dictionary] = []
	for drop: Dictionary in rolled.value:
		var definition := _items.definition(drop.item_definition_id)
		if definition.is_empty():
			return DomainResult.failure(&"reward.unknown_item", "掉落物品未登记")
		var maximum := maxi(1, int(definition.get("max_stack", 1)))
		var remaining := int(drop.quantity)
		while remaining > 0:
			var stack := drop.duplicate(true)
			stack.quantity = mini(remaining, maximum)
			remaining -= int(stack.quantity)
			result.append(stack)
	return DomainResult.ok(result)
