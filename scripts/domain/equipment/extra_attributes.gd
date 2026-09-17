class_name ExtraAttributes
extends RefCounted

var _levels: Dictionary[String, int] = {}


## 恢复各独立通道的使用颗数，不能把原版加工写成基础加工或原创人物宝石。
## [param raw] 原始存档事实。
## 返回成长对象或格式错误。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary or raw.get("version", 1) != 1 or not raw.get("levels", {}) is Dictionary:
		return DomainResult.failure(&"extra.invalid_state", "额外属性记录无效")
	var result := ExtraAttributes.new()
	for key: Variant in raw.get("levels", {}):
		var level: Variant = raw.levels[key]
		if not key is String or not (level is int or level is float) or not is_finite(float(level)) \
			or float(level) != int(level) or level < 0 or level > 30:
			return DomainResult.failure(&"extra.invalid_state", "额外属性颗数无效")
		if level > 0: result._levels[key] = int(level)
	return DomainResult.ok(result)


## 按装备资格复核每一条原始成长事实。
## [param id] 装备定义。
## [param rules] 服务端目录。
## 返回合法状态或不兼容/越界错误。
func validate_for(id: String, rules: ExtraAttributeRules) -> DomainResult:
	for channel: String in _levels:
		if channel not in rules.allowed(id) or _levels[channel] > rules.channels[channel].maximum:
			return DomainResult.failure(&"extra.incompatible", "装备不支持该额外属性或已超上限")
	return DomainResult.ok()


## 查询通道当前颗数。
## [param channel] 萤石或耀石通道。
## 返回当前等级，未加工为零。
func level(channel: String) -> int:
	return _levels.get(channel, 0)


## 汇总指定属性的固定增量，概率使用 0～1 范围。
## [param attribute] 统一属性。
## [param rules] 当前目录；构造尚未组装规则时可为空。
## 返回可叠加的增量。
func bonus(attribute: String, rules: ExtraAttributeRules) -> float:
	if rules == null: return 0
	var result := 0.0
	for id: String in _levels:
		if rules.channels.has(id) and rules.channels[id].attribute == attribute:
			result += _levels[id] * rules.channels[id].points
	return result


## 校验资格并预览成功与失败两条结果。
## [param definition_id] 装备定义。
## [param channel] 所选材料的通道。
## [param rules] 规则。
## 返回颗数、加值及成功率，满级不可操作。
func preview(definition_id: String, channel: ExtraAttributeRules.Channel, rules: ExtraAttributeRules) -> DomainResult:
	if channel == null or channel.id not in rules.allowed(definition_id):
		return DomainResult.failure(&"extra.incompatible", "该装备不接受所选萤石或耀石")
	var current := level(channel.id)
	if current >= channel.maximum:
		return DomainResult.failure(&"extra.maximum", "该额外属性已达上限")
	var band := rules.success_band(current)
	return DomainResult.ok({"before": current, "after": current + 1, "failed_level": maxi(0, current - int(band.failure_loss)),
		"maximum": channel.maximum, "chance": band.chance, "points": channel.points, "attribute": channel.attribute})


## 在材料已预检后依服务端随机样本提交一颗成长，失败按原版档位保留或退一颗。
## [param definition_id] 装备定义。
## [param channel] 本次加工通道。
## [param rules] 原版规则。
## [param roll] 服务端随机样本。
## 返回实际结果或未修改的错误。
func apply(definition_id: String, channel: ExtraAttributeRules.Channel, rules: ExtraAttributeRules, roll: float) -> DomainResult:
	if not is_finite(roll) or roll < 0 or roll >= 1:
		return DomainResult.failure(&"extra.invalid_roll", "额外属性随机样本无效")
	var quote := preview(definition_id, channel, rules)
	if not quote.is_ok: return quote
	var result: Dictionary = quote.value
	result["success"] = roll < float(result.chance)
	_levels[channel.id] = int(result.after if result.success else result.failed_level)
	result["actual_level"] = _levels[channel.id]
	return DomainResult.ok(result)


## 导出各通道颗数，不重复保存派生属性。
## 返回独立存档字典。
func to_dictionary() -> Dictionary:
	return {"version": 1, "levels": _levels.duplicate(true)}
