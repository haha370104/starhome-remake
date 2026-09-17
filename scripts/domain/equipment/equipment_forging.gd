class_name EquipmentForging
extends RefCounted

var extensions: Dictionary[int, int] = {}


## 恢复原始扩展点数，不保存已经叠加加工或品质的结果。
## [param raw] 旧档默认空对象。
## 返回独立锻造事实或非法状态。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary or raw.get("version", 1) != 1 or not raw.get("extensions", {}) is Dictionary:
		return DomainResult.failure(&"forging.state", "装备锻造状态格式无效")
	var result := EquipmentForging.new()
	for key: Variant in raw.get("extensions", {}):
		var value: Variant = raw.extensions[key]
		var kind := str(key).to_int()
		if not key is String or key != str(kind) or kind < 1 or kind > 8 or not (value is int or value is float) \
			or not is_finite(float(value)) or float(value) != int(value) or value < 0 or value > 1000000:
			return DomainResult.failure(&"forging.state", "装备锻造扩展值无效")
		if value > 0: result.extensions[kind] = int(value)
	return DomainResult.ok(result)


## 校验每种扩展方向和原版最大值，禁止把底盘成长写到武器上。
## [param profile] 同定义装备资格。
## 返回合法或越界错误。
func validate_for(profile: EquipmentForgingRules.Profile) -> DomainResult:
	for kind: int in extensions:
		if profile == null or not profile.limits.has(kind) or extensions[kind] > profile.limits[kind]:
			return DomainResult.failure(&"forging.limit", "锻造属性不适用或超出原版上限")
	return DomainResult.ok()


## 执行已经支付的单次扩展或失败回退，最终一次只补到上限。
## [param channel] 所选类型和复刻步长。
## [param profile] 当前装备上限。
## [param success] 服务器成功判定。
## 返回新旧扩展值或已满拒绝；不负责其他成长的事务清除。
func apply(channel: EquipmentForgingRules.Channel, profile: EquipmentForgingRules.Profile, success: bool) -> DomainResult:
	if channel == null or profile == null or not profile.limits.has(channel.type):
		return DomainResult.failure(&"forging.incompatible", "该芯片不能锻造当前装备")
	var before: int = extensions.get(channel.type, 0)
	if before >= profile.limits[channel.type]: return DomainResult.failure(&"forging.maximum", "该项锻造已满")
	var after := clampi(before + (channel.step if success else -channel.step), 0, profile.limits[channel.type])
	if after > 0: extensions[channel.type] = after
	else: extensions.erase(channel.type)
	return DomainResult.ok({"before": before, "after": after, "maximum": profile.limits[channel.type]})


## 计算源客户端直接加入攻击或火箭射程的扩展，其他方向只改变加工上限。
## [param attribute] 实际战斗属性。
## [param rules] 已验证规则。
## 返回直接增量。
func direct_bonus(attribute: String, rules: EquipmentForgingRules) -> int:
	var result := 0
	if rules == null: return result
	for kind: int in extensions:
		var channel: EquipmentForgingRules.Channel = rules.channels.get(kind)
		if channel != null and channel.attribute == attribute and channel.direct_bonus: result += extensions[kind]
	return result


## 生成该实例的独立加工上限，保留原始配方价格和需求等级。
## [param base] 目录中的不可变原版加工配置。
## [param rules] 锻造方向规则。
## 返回独立配置；没有加工资格仍返回null。
func expanded_processing(base: EquipmentProcessingRules.Profile, rules: EquipmentForgingRules) -> EquipmentProcessingRules.Profile:
	if base == null or rules == null or extensions.is_empty(): return base
	var result := EquipmentProcessingRules.Profile.new()
	for attribute: String in base.attributes:
		var original: EquipmentProcessingRules.AttributeRule = base.attributes[attribute]
		var copy := EquipmentProcessingRules.AttributeRule.new()
		copy.attribute = original.attribute
		copy.label = original.label
		copy.base = original.base
		copy.limit = original.limit
		copy.required_skill_level = original.required_skill_level
		copy.currency = original.currency
		copy.materials = original.materials.duplicate(true)
		for kind: int in extensions:
			var channel: EquipmentForgingRules.Channel = rules.channels.get(kind)
			if channel != null and channel.attribute == attribute and channel.expands_processing: copy.limit += extensions[kind]
		result.attributes[attribute] = copy
	return result


## 输出持久化事实，空值与老存档等价。
## 返回字符串键的JSON安全字典。
func to_dictionary() -> Dictionary:
	if extensions.is_empty(): return {}
	var values := {}
	for kind: int in extensions: values[str(kind)] = extensions[kind]
	return {"version": 1, "extensions": values}
