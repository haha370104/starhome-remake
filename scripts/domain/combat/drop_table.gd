class_name DropTable
extends RefCounted


var _entries: Array[Dictionary] = []


## 初始化服务端已确认的怪物掉落表。
## [param raw_entries] 配置中的掉落数组；null 表示尚无可信掉落数据。
## 设计：未经确认的旧客户端候选表达式不得进入本对象。
func _init(raw_entries: Variant = null) -> void:
	configure(raw_entries)


## 校验并装载权威掉落条目。
## [param raw_entries] null 或由物品定义、数量范围和独立概率组成的数组。
## 返回成功或首个无效条目的配置错误。
func configure(raw_entries: Variant) -> DomainResult:
	_entries.clear()
	if raw_entries == null:
		return DomainResult.ok(self)
	if not raw_entries is Array:
		return DomainResult.failure(&"combat.invalid_drop_table", "monster drops must be null or an array")
	for raw_entry: Variant in raw_entries:
		if not raw_entry is Dictionary:
			return DomainResult.failure(&"combat.invalid_drop_table", "drop entry must be a dictionary")
		var entry: Dictionary = raw_entry
		var definition_id := String(entry.get("item_definition_id", ""))
		var minimum_quantity := int(entry.get("minimum_quantity", 0))
		var maximum_quantity := int(entry.get("maximum_quantity", 0))
		var chance := float(entry.get("chance", -1.0))
		if definition_id.is_empty() or minimum_quantity <= 0 \
			or maximum_quantity < minimum_quantity or chance < 0.0 or chance > 1.0:
			return DomainResult.failure(&"combat.invalid_drop_table", "drop entry fields are invalid")
		_entries.append({
			"item_definition_id": definition_id,
			"minimum_quantity": minimum_quantity,
			"maximum_quantity": maximum_quantity,
			"chance": chance,
		})
	return DomainResult.ok(self)


## 查询当前是否存在可由权威服务器结算的掉落。
## 返回至少有一条可信配置时为 true。
func is_configured() -> bool:
	return not _entries.is_empty()


## 导出只读掉落配置副本。
## 返回掉落条目数组。
func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


## 使用权威服务器随机源独立抽取每条掉落配置。
## [param random] 由当前地图战斗模块持有并播种的随机数生成器。
## 返回本次实际生成的物品定义与数量数组。
## 设计：领域对象只返回值对象，不生成世界实体或直接修改玩家背包。
func roll(random: RandomNumberGenerator) -> Array[Dictionary]:
	var rolled := roll_with_modifiers(random, null, null)
	return rolled.value if rolled.is_ok else []


## 在独立随机判定前执行统一倍率切面，概率溢出转为保证数量。
## [param random] 服务端随机源。
## [param pipeline] 可选奖励切面；为空时保持原始抽取行为。
## [param context] 击杀者及怪物的权威事实，各物品使用独立上下文。
## 返回本次掉落数组或结算错误；失败不返回半批奖励。
func roll_with_modifiers(random: RandomNumberGenerator, pipeline: RewardPipeline, context: RewardContext) -> DomainResult:
	var result: Array[Dictionary] = []
	if random == null:
		return DomainResult.ok(result)
	if pipeline != null and context == null:
		return DomainResult.failure(&"reward.invalid_context", "掉落倍率缺少权威上下文")
	for entry: Dictionary in _entries:
		var chance := float(entry.chance)
		var settlement: RewardSettlement
		if pipeline != null:
			var settled := pipeline.settle(context.for_item(String(entry.item_definition_id)), chance)
			if not settled.is_ok:
				return settled
			settlement = settled.value
			chance = settlement.final_amount
		if chance <= 0.0:
			continue
		# 保持默认倍率时原随机数消费顺序，且不把大于100%的概率截断。
		if chance * int(entry.maximum_quantity) > 9007199254740991.0:
			return DomainResult.failure(&"reward.overflow", "掉落数量超过精确整数范围")
		var successes := floori(chance)
		if random.randf() < chance - successes:
			successes += 1
		if successes == 0:
			continue
		var drop := {
			"item_definition_id": String(entry.item_definition_id),
			"quantity": random.randi_range(int(entry.minimum_quantity), int(entry.maximum_quantity)) * successes,
		}
		if settlement != null:
			drop["reward_settlement"] = settlement.to_dictionary()
		result.append(drop)
	return DomainResult.ok(result)
