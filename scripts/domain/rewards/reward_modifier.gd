class_name RewardModifier
extends RefCounted

var id := ""
var channel: StringName
var multiplier := 1.0
var stack_group := ""
var account_ids: PackedStringArray = []
var skill_ids: PackedStringArray = []
var item_ids: PackedStringArray = []
var species_ids: PackedStringArray = []
var sources: PackedStringArray = []
var population_kinds: PackedStringArray = []
var starts_at := 0
var expires_at := 0


## 严格解析倍率配置；非法规则不能静默成为全局加成。
## [param raw] 仅来自服务端配置或受信任增益提供者的规则。
## 返回类型化规则或格式错误。
static func parse(raw: Dictionary) -> DomainResult:
	var allowed := ["id", "channel", "multiplier", "stack_group", "account_ids", "skill_ids", "item_ids", "species_ids", "sources", "population_kinds", "starts_at", "expires_at"]
	for key: Variant in raw:
		if key not in allowed:
			return DomainResult.failure(&"reward.invalid_rule", "未知奖励规则字段：%s" % key)
	if not raw.get("id") is String or String(raw.id).is_empty() or raw.get("channel") not in ["experience", "drop"]:
		return DomainResult.failure(&"reward.invalid_rule", "奖励规则身份或通道无效")
	var value: Variant = raw.get("multiplier")
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0:
		return DomainResult.failure(&"reward.invalid_rule", "倍率必须有限且非负")
	var rule := RewardModifier.new()
	rule.id = raw.id
	rule.channel = StringName(raw.channel)
	rule.multiplier = float(value)
	if not raw.get("stack_group", "") is String:
		return DomainResult.failure(&"reward.invalid_rule", "互斥组必须是字符串")
	rule.stack_group = raw.get("stack_group", "")
	for key: String in ["account_ids", "skill_ids", "item_ids", "species_ids", "sources", "population_kinds"]:
		var selector: Variant = raw.get(key, [])
		if not selector is Array:
			return DomainResult.failure(&"reward.invalid_rule", "筛选条件必须为字符串数组")
		var values := PackedStringArray()
		for entry: Variant in selector:
			if not entry is String or String(entry).is_empty():
				return DomainResult.failure(&"reward.invalid_rule", "筛选项不能为空")
			values.append(entry)
		rule.set(key, values)
	if (rule.channel == &"experience" and not rule.item_ids.is_empty()) or (rule.channel == &"drop" and not rule.skill_ids.is_empty()):
		return DomainResult.failure(&"reward.invalid_rule", "筛选项与奖励通道不兼容")
	for key: String in ["starts_at", "expires_at"]:
		var timestamp: Variant = raw.get(key, 0)
		if typeof(timestamp) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(timestamp)) or float(timestamp) < 0 or float(timestamp) != floorf(float(timestamp)):
			return DomainResult.failure(&"reward.invalid_rule", "有效期必须为非负整数秒")
		rule.set(key, int(timestamp))
	if rule.expires_at > 0 and rule.expires_at <= rule.starts_at:
		return DomainResult.failure(&"reward.invalid_rule", "规则有效期为空")
	return DomainResult.ok(rule)


## 判断规则是否适用于本次账号、技能、物品及奖励来源。
## [param context] 本次结算的权威事实。
## 返回全部筛选条件匹配且仍在有效期内时为真。
func matches(context: RewardContext) -> bool:
	return context.channel == channel and context.now >= starts_at \
		and (expires_at == 0 or context.now < expires_at) \
		and (account_ids.is_empty() or context.account_id in account_ids) \
		and (skill_ids.is_empty() or context.skill_id in skill_ids) \
		and (item_ids.is_empty() or context.item_id in item_ids) \
		and (species_ids.is_empty() or context.species_id in species_ids) \
		and (sources.is_empty() or context.source in sources) \
		and (population_kinds.is_empty() or String(context.population_kind) in population_kinds)
