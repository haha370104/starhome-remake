class_name ClothingEnhancement
extends RefCounted

const PREFIXES := ["tiger", "turtle", "dragon", "phoenix"]
const TRAITS := ["economy", "repair", "pursuit", "purification", "prospecting"]
const GEMS := ["max_health", "defense", "movement_speed", "energy_cannon_attack", "missile_attack", "rocket_attack", "self_repair", "mining_power", "working_energy_capacity", "output_power", "energy_cannon_range"]
const QUALITIES := ["破损", "瑕疵", "平凡", "明亮", "闪耀", "完美"]

var prefix := ""
var prefix_quality := 0
var trait_id := ""
var trait_quality := 0
var gem := ""
var gem_stage := 0


## 校验持久化或协议边界，旧装备空状态视为未强化。
## [param raw] 尚未可信的强化状态。
## 返回合法的类型化强化状态或具体错误；不默默吞掉损坏数据。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary:
		return DomainResult.failure(&"enhancement.invalid_state", "人物装备强化状态格式错误")
	var result := ClothingEnhancement.new()
	if int(raw.get("version", 1)) != 1:
		return DomainResult.failure(&"enhancement.invalid_state", "不支持的人物装备强化版本")
	for key: String in ["prefix", "trait", "gem"]:
		if not raw.get(key, "") is String:
			return DomainResult.failure(&"enhancement.invalid_state", "强化类型必须是文本标识")
	for key: String in ["prefix_quality", "trait_quality", "gem_stage"]:
		var value: Variant = raw.get(key, 0)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or float(value) != floorf(float(value)):
			return DomainResult.failure(&"enhancement.invalid_state", "强化等级必须是整数")
	result.prefix = String(raw.get("prefix", ""))
	result.prefix_quality = int(raw.get("prefix_quality", 0))
	result.trait_id = String(raw.get("trait", ""))
	result.trait_quality = int(raw.get("trait_quality", 0))
	result.gem = String(raw.get("gem", ""))
	result.gem_stage = int(raw.get("gem_stage", 0))
	if not _valid_pair(result.prefix, result.prefix_quality, PREFIXES, 6) \
		or not _valid_pair(result.trait_id, result.trait_quality, TRAITS, 6) \
		or not _valid_pair(result.gem, result.gem_stage, GEMS, 15):
		return DomainResult.failure(&"enhancement.invalid_state", "强化类型与等级不匹配")
	return DomainResult.ok(result)


## 预检石头对当前装备状态的变更，不消耗材料。
## [param stone] 已由物品目录构造的强化石。
## 返回操作前后状态与高级宝石低段使用提示。
func preview(stone: EnhancementStone) -> DomainResult:
	if stone == null or stone.locked:
		return DomainResult.failure(&"enhancement.stone_unavailable", "请选择未锁定的强化石")
	var after: ClothingEnhancement = restore(to_dictionary()).value
	match stone.family:
		"prefix":
			if prefix == stone.effect and prefix_quality >= stone.rank:
				return DomainResult.failure(&"enhancement.no_improvement", "同类型前缀只能提高品质")
			after.prefix = stone.effect
			after.prefix_quality = stone.rank
		"trait":
			if trait_id == stone.effect and trait_quality >= stone.rank:
				return DomainResult.failure(&"enhancement.no_improvement", "同类型特性只能提高品质")
			after.trait_id = stone.effect
			after.trait_quality = stone.rank
		"gem":
			if not gem.is_empty() and gem != stone.effect:
				return DomainResult.failure(&"enhancement.gem_route", "宝石路线不同，请先重置当前路线")
			if gem_stage >= 15 or stone.rank < gem_stage + 1:
				return DomainResult.failure(&"enhancement.gem_rank", "宝石等级不足或装备已达15段")
			after.gem = stone.effect
			after.gem_stage += 1
		_:
			return DomainResult.failure(&"enhancement.invalid_stone", "该物品不是可用的强化石")
	return DomainResult.ok({"before": to_dictionary(), "after": after.to_dictionary(),
		"wastes_rank": stone.family == "gem" and stone.rank > gem_stage + 1})


## 将已预检石头作用到当前实例，保留其余两套强化。
## [param stone] 当前事务将消耗的一颗石头。
## 返回与预览一致的结果或拒绝原因。
func apply_stone(stone: EnhancementStone) -> DomainResult:
	var checked := preview(stone)
	if not checked.is_ok:
		return checked
	var after: ClothingEnhancement = restore(checked.value.after).value
	prefix = after.prefix
	prefix_quality = after.prefix_quality
	trait_id = after.trait_id
	trait_quality = after.trait_quality
	gem = after.gem
	gem_stage = after.gem_stage
	return checked


## 明确清除当前宝石路线，不返还已消耗材料，不影响前后缀。
func reset_gem() -> void:
	gem = ""
	gem_stage = 0


## 将整条路线迁入空目标；来源与目标必须由上层验证同部位及所有权。
## [param target] 不同装备的强化状态。
## 返回迁移结果，失败不修改任一实例。
func transfer_gem_to(target: ClothingEnhancement) -> DomainResult:
	if target == null or target == self or gem_stage == 0 or target.gem_stage > 0:
		return DomainResult.failure(&"enhancement.transfer_rejected", "来源须有宝石，目标须为空路线且不能是同一装备")
	target.gem = gem
	target.gem_stage = gem_stage
	reset_gem()
	return DomainResult.ok()


## 导出原始强化事实，禁止持久化叠加后的战斗数值。
## 返回带规则版本的边界状态。
func to_dictionary() -> Dictionary:
	return {"version": 1, "prefix": prefix, "prefix_quality": prefix_quality,
		"trait": trait_id, "trait_quality": trait_quality, "gem": gem, "gem_stage": gem_stage}


## 校验空类型对应零级、已知类型对应有效正等级。
## [param id] 效果类型。
## [param rank] 品质或镶嵌段数。
## [param allowed] 类型白名单。
## [param maximum] 允许的最大等级。
## 返回身份与等级是否同时有效。
static func _valid_pair(id: String, rank: int, allowed: Array, maximum: int) -> bool:
	return (id.is_empty() and rank == 0) or (id in allowed and rank >= 1 and rank <= maximum)
