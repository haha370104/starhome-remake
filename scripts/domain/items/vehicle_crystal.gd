class_name VehicleCrystal
extends GameItem

var cracks: int = 0


## 在存档和目录边界统一验证裂纹，不将非法值强制截断。
## [param raw] 原始裂纹数。
## 返回整数裂纹或格式错误。
static func restore_cracks(raw: Variant) -> DomainResult:
	if not (raw is int or raw is float) or not is_finite(float(raw)) \
		or float(raw) != floorf(float(raw)) or raw < 0 or raw > 3:
		return DomainResult.failure(&"sockets.invalid_state", "晶石裂纹必须为 0～3 的整数")
	return DomainResult.ok(int(raw))


## 初始化已通过目录校验的普通战车晶石。
## [param definition] 晶石定义。
## [param state] 包含裂纹的实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	cracks = int(state.get("crystal_cracks", 0))


## 只有相同裂纹和绑定的晶石可以合并，防止借堆叠清除裂纹。
## [param other] 候选堆叠。
## 返回是否兼容。
func can_stack_with(other: GameItem) -> bool:
	return other is VehicleCrystal and cracks == other.cracks and super(other)


## 拆分保留原裂纹与具体类型。
## [param new_id] 权威新标识。
## [param amount] 拆分数量。
## 返回独立晶石堆叠。
func copy_stack(new_id: String, amount: int) -> GameItem:
	return VehicleCrystal.new(_definition, {"instance_id": new_id, "quantity": amount,
		"bound": bound, "locked": locked, "container_id": container_id, "crystal_cracks": cracks,
		"position_px": [position_px.x, position_px.y], "footprint_px": [footprint_px.x, footprint_px.y]})


## 导出裂纹以支持查看与快照还原。
## 返回晶石视图。
func to_view_dictionary() -> Dictionary:
	var view := super()
	view["crystal_cracks"] = cracks
	view["vehicle_crystal"] = true
	view["description"] = description + "\n裂纹：%d / 3；已有三裂时再次普通摘取会损毁。" % cracks
	return view
