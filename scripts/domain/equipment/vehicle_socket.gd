class_name VehicleSocket
extends RefCounted

var opened: bool = false
var crystal_id: String = ""
var cracks: int = 0
var bound: bool = false


## 校验一个孔的持久化事实；不解释晶石配置。
## [param raw] 存档或协议中的单孔数据。
## 返回独立孔对象或错误，不截断非法值。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary or not raw.get("opened", false) is bool \
		or not raw.get("bound", false) is bool or not raw.get("crystal_id", "") is String:
		return DomainResult.failure(&"sockets.invalid_state", "孔槽记录格式无效")
	var count: Variant = raw.get("cracks", 0)
	if not (count is int or count is float) or not is_finite(float(count)) \
		or float(count) != floorf(float(count)) or count < 0 or count > 3:
		return DomainResult.failure(&"sockets.invalid_state", "晶石裂纹必须为 0～3 的整数")
	var result := VehicleSocket.new()
	result.opened = raw.get("opened", false)
	result.crystal_id = raw.get("crystal_id", "")
	result.cracks = int(count)
	result.bound = raw.get("bound", false)
	if (not result.opened and not result.crystal_id.is_empty()) \
		or (result.crystal_id.is_empty() and (result.cracks != 0 or result.bound)):
		return DomainResult.failure(&"sockets.invalid_state", "未镶嵌孔不能包含晶石状态")
	return DomainResult.ok(result)


## 导出孔的原始事实，不保存任何重复计算的属性。
## 返回 JSON 兼容快照。
func to_dictionary() -> Dictionary:
	return {"opened": opened, "crystal_id": crystal_id, "cracks": cracks, "bound": bound}
