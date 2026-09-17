class_name EquipmentUsage
extends RefCounted

const EVENTS := ["shot", "movement", "mining", "damage"]
var progress: Dictionary = {}


## 恢复尚不足扣除一点耐久的累计使用量，旧档为空时从零开始。
## [param raw] 只保存使用余量的原始状态。
## 返回有效状态或格式错误。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary or int(raw.get("version", 1)) != 1 or not raw.get("progress", {}) is Dictionary:
		return DomainResult.failure(&"equipment.invalid_usage", "装备使用记录无效")
	var usage := EquipmentUsage.new()
	for event: Variant in raw.get("progress", {}):
		var amount: Variant = raw.progress[event]
		if event not in EVENTS or not (amount is int or amount is float) \
			or not is_finite(float(amount)) or float(amount) < 0 or float(amount) > 1000000:
			return DomainResult.failure(&"equipment.invalid_usage", "装备使用余量无效")
		usage.progress[event] = float(amount)
	return DomainResult.ok(usage)


## 累加权威确认的使用量，只输出完整耐久单位，并留下不足一个单位的余量。
## [param event] 使用类型。
## [param amount] 已发生的次数或移动秒数。
## [param threshold] 消耗一点耐久所需的使用量。
## 返回本次应扣除的耐久。
func consume(event: String, amount: float, threshold: float) -> int:
	if event not in EVENTS or not is_finite(amount) or not is_finite(threshold) or amount <= 0 or threshold <= 0:
		return 0
	var accumulated := float(progress.get(event, 0)) + amount
	var wear := floori((accumulated + 0.0000001) / threshold)
	progress[event] = maxf(0, accumulated - wear * threshold)
	return wear


## 导出原始使用余量。
## 返回独立存档字典。
func to_dictionary() -> Dictionary:
	return {"version": 1, "progress": progress.duplicate(true)}
