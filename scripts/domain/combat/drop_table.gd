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
	var result: Array[Dictionary] = []
	if random == null:
		return result
	for entry: Dictionary in _entries:
		var chance := float(entry["chance"])
		if chance <= 0.0 or random.randf() >= chance:
			continue
		result.append({
			"item_definition_id": String(entry["item_definition_id"]),
			"quantity": random.randi_range(
				int(entry["minimum_quantity"]), int(entry["maximum_quantity"])
			),
		})
	return result
