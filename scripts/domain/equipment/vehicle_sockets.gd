class_name VehicleSockets
extends RefCounted

var _slots: Array[VehicleSocket] = []


## 恢复孔槽结构；旧存档缺字段时保留为空，装备目录再赋予未开启基础孔。
## [param raw] JSON 边界状态。
## 返回校验后的独立状态或错误。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary:
		return DomainResult.failure(&"sockets.invalid_state", "战车孔槽必须为对象")
	var result := VehicleSockets.new()
	if raw.is_empty():
		return DomainResult.ok(result)
	if raw.get("version") != 1 or not raw.get("slots") is Array or raw.slots.size() > 12:
		return DomainResult.failure(&"sockets.invalid_state", "战车孔槽版本或数量无效")
	for entry: Variant in raw.slots:
		var checked := VehicleSocket.restore(entry)
		if not checked.is_ok:
			return checked
		result._slots.append(checked.value)
	return DomainResult.ok(result)


## 将存档结构与当前装备资格和晶石目录交叉校验。
## [param profile] 装备开槽资格；null 表示禁止开槽。
## [param rules] 权威规则目录。
## 返回成功或越界、错误材料等拒绝原因。
func validate_for(profile: VehicleSocketRules.Profile, rules: VehicleSocketRules) -> DomainResult:
	if profile == null:
		return DomainResult.ok() if _slots.is_empty() else DomainResult.failure(&"sockets.unsupported", "该装备不允许保存普通晶石孔")
	if _slots.is_empty():
		for index: int in profile.base_capacity:
			_slots.append(VehicleSocket.new())
	if _slots.size() < profile.base_capacity or _slots.size() > profile.maximum_capacity:
		return DomainResult.failure(&"sockets.invalid_state", "孔槽数量超出装备资格")
	for slot: VehicleSocket in _slots:
		if not slot.crystal_id.is_empty() and rules.crystal(slot.crystal_id) == null:
			return DomainResult.failure(&"sockets.invalid_crystal", "孔槽中含未知普通晶石")
	return DomainResult.ok()


## 查询已解锁的孔数，包含未开启孔。
## 返回孔数。
func capacity() -> int:
	return _slots.size()


## 查询已开启孔数，用于成功率和失败回退。
## 返回已开孔数。
func opened_count() -> int:
	var total := 0
	for slot: VehicleSocket in _slots:
		total += int(slot.opened)
	return total


## 获取一个孔的独立快照，调用方不可直接修改内部状态。
## [param index] 从零开始的孔序号。
## 返回复制的孔或 null。
func slot_at(index: int) -> VehicleSocket:
	if index < 0 or index >= _slots.size():
		return null
	return VehicleSocket.restore(_slots[index].to_dictionary()).value


## 校验开槽目标并返回概率，预检不消耗物品。
## [param index] 目标孔。
## [param profile] 该装备资格。
## [param material] 使用的柔解剂。
## [param rules] 规则目录。
## 返回成功率或不适用原因。
func preview_open(index: int, profile: VehicleSocketRules.Profile, material: VehicleSocketRules.Solvent, rules: VehicleSocketRules) -> DomainResult:
	if index < 0 or index >= capacity() or _slots[index].opened:
		return DomainResult.failure(&"sockets.invalid_slot", "请选择未开启的孔")
	var chance := rules.opening_chance(profile, material, opened_count())
	if chance <= 0:
		return DomainResult.failure(&"sockets.invalid_solvent", "这种柔解剂不适用于当前装备或孔数")
	return DomainResult.ok(chance)


## 在支付之后结算已预检的开槽尝试；失败关闭最高编号的已开孔。
## [param index] 目标孔。
## [param success] 权威随机结果。
## [param failure] 规则中的失败后果。
## 返回是否需要销毁整件装备。
func settle_open(index: int, success: bool, failure: String) -> bool:
	if success:
		_slots[index].opened = true
		return false
	if failure == "close_last_socket":
		for previous: int in range(_slots.size() - 1, -1, -1):
			if _slots[previous].opened:
				_slots[previous] = VehicleSocket.new()
				break
	return failure == "destroy_equipment"


## 为已解锁空孔嵌入一颗晶石，保留其裂纹和绑定事实。
## [param index] 目标孔。
## [param crystal] 一颗普通晶石，数量由聚合支付。
## 返回成功或不可镶嵌原因。
func inlay(index: int, crystal: VehicleCrystal) -> DomainResult:
	if index < 0 or index >= capacity() or not _slots[index].opened or not _slots[index].crystal_id.is_empty():
		return DomainResult.failure(&"sockets.invalid_slot", "请选择已开启的空孔")
	if crystal == null or crystal.locked:
		return DomainResult.failure(&"sockets.invalid_crystal", "请选择未锁定的战车晶石")
	_slots[index].crystal_id = crystal.definition_id
	_slots[index].cracks = crystal.cracks
	_slots[index].bound = crystal.bound
	return DomainResult.ok()


## 摘取后清空已预检孔，孔本身保持开启。
## [param index] 已镶嵌晶石的孔序号。
func clear_crystal(index: int) -> void:
	_slots[index] = VehicleSocket.new()
	_slots[index].opened = true


## 在支付扩孔材料后增加一个未开启孔。
## [param profile] 装备扩孔资格。
## 返回成功或资格/上限错误。
func expand(profile: VehicleSocketRules.Profile) -> DomainResult:
	if profile == null or not profile.expansion or capacity() >= profile.maximum_capacity:
		return DomainResult.failure(&"sockets.expansion_unavailable", "该装备不能继续扩孔")
	_slots.append(VehicleSocket.new())
	return DomainResult.ok(capacity())


## 导出原始孔状态供存档与界面复用。
## 返回 JSON 兼容数据。
func to_dictionary() -> Dictionary:
	var rows: Array[Dictionary] = []
	for slot: VehicleSocket in _slots:
		rows.append(slot.to_dictionary())
	return {} if rows.is_empty() else {"version": 1, "slots": rows}
