class_name WeaponMagazine
extends RefCounted

var remaining: int = -1


## 恢复当前弹量；未出现过弹仓字段的旧档使用 -1，绑定装备时仅初始化一次。
## [param raw] 原始弹仓事实。
## 返回弹仓或非法状态。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary or int(raw.get("version", 1)) != 1:
		return DomainResult.failure(&"ammunition.invalid_state", "弹仓记录无效")
	var count: Variant = raw.get("remaining", -1)
	if not (count is int or count is float) or not is_finite(float(count)) or float(count) != int(count) or int(count) < -1:
		return DomainResult.failure(&"ammunition.invalid_state", "弹药数量无效")
	var magazine := WeaponMagazine.new()
	magazine.remaining = int(count)
	return DomainResult.ok(magazine)


## 绑定装备派生容量，扩容不自动补弹，显式存量不能超上限。
## [param capacity] 基础容量与加工增量之和。
## 返回成功或存量越界。
func bind_capacity(capacity: int) -> DomainResult:
	if remaining == -1: remaining = maxi(0, capacity)
	if capacity < 0 or remaining > capacity:
		return DomainResult.failure(&"ammunition.invalid_state", "弹量超过装备容量")
	return DomainResult.ok()


## 执行已经通过冷却、目标和能量校验的一次射击。
## 返回扣弹成功或弹仓已空。
func consume() -> DomainResult:
	if remaining <= 0:
		return DomainResult.failure(&"ammunition.empty", "弹药不足，请到基地或生产区补弹")
	remaining -= 1
	return DomainResult.ok()


## 在费用成功结算后补足派生容量。
## [param capacity] 权威目标容量。
func refill(capacity: int) -> void:
	remaining = maxi(0, capacity)


## 导出当前弹量，容量由装备定义与加工事实派生。
## 返回独立存档字典。
func to_dictionary() -> Dictionary:
	return {"version": 1, "remaining": remaining}
