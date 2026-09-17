class_name PersonalWarehouseRecord
extends RefCounted

class Cabinet extends RefCounted:
	var stacks: Array[InventoryStackRecord] = []

var _revision := 0
var _cabinets: Array[Cabinet] = [Cabinet.new()]


## 从JSON边界恢复独立柜及完整物品记录，旧存档缺字段时提供一个空柜。
## [param raw] 原始仓库字段。
## 返回结构有效的记录，不接受重复身份、非法版本或未开通柜中的物品。
static func from_dictionary(raw: Variant) -> DomainResult:
	if not raw is Dictionary:
		return DomainResult.failure(&"warehouse.state", "仓库存档必须是对象")
	var result := PersonalWarehouseRecord.new()
	if raw.is_empty(): return DomainResult.ok(result)
	var version: Variant = raw.get("revision")
	if raw.get("version") != 1 or not (version is int or version is float) or not is_finite(float(version)) or version < 0 or float(version) != floorf(float(version)):
		return DomainResult.failure(&"warehouse.state", "仓库存档版本无效")
	var rows: Variant = raw.get("cabinets")
	if not rows is Array or rows.is_empty() or rows.size() > PersonalWarehouse.MAX_CABINETS:
		return DomainResult.failure(&"warehouse.state", "仓库存档柜数无效")
	result._revision = int(version)
	result._cabinets.clear()
	var ids: Dictionary[String, bool] = {}
	for row: Variant in rows:
		if not row is Array or row.size() > InventoryLayout.ITEM_LIMIT:
			return DomainResult.failure(&"warehouse.state", "储物柜物品超出容量")
		var cabinet := Cabinet.new()
		var slots: Dictionary[int, bool] = {}
		for value: Variant in row:
			if not value is Dictionary:
				return DomainResult.failure(&"warehouse.state", "仓库物品记录必须是对象")
			for key: String in ["quantity", "slot_index"]:
				var number: Variant = value.get(key)
				if not (number is int or number is float) or not is_finite(float(number)) or float(number) != floorf(float(number)):
					return DomainResult.failure(&"warehouse.state", "仓库物品数量和位置必须为整数")
			var loaded := InventoryStackRecord.from_dictionary(value)
			if not loaded.is_ok: return loaded
			var stack: InventoryStackRecord = loaded.value
			if ids.has(stack.stack_id) or slots.has(stack.slot_index) or stack.slot_index >= InventoryLayout.ITEM_LIMIT:
				return DomainResult.failure(&"warehouse.identity", "储物柜位置或物品身份重复")
			ids[stack.stack_id] = true
			slots[stack.slot_index] = true
			cabinet.stacks.append(stack)
		result._cabinets.append(cabinet)
	return DomainResult.ok(result)


## 从领域仓库捕获完整实例状态，复用背包的字段映射。
## [param warehouse] 当前人物的独立仓库。
## 返回经过格式验证的持久化记录。
static func from_domain(warehouse: PersonalWarehouse) -> DomainResult:
	if warehouse is StoredPersonalWarehouse:
		var unchanged: PersonalWarehouseRecord = warehouse.unchanged_record()
		if unchanged != null: return DomainResult.ok(unchanged)
	var loaded := warehouse.materialize()
	if not loaded.is_ok: return loaded
	var rows: Array = []
	for index in range(1, warehouse.cabinet_count() + 1):
		var stacks: Array[Dictionary] = []
		for item: GameItem in warehouse.items(index):
			var recorded := InventoryStackRecord.from_item(item, stacks.size())
			if not recorded.is_ok: return recorded
			stacks.append(recorded.value.to_dictionary())
		rows.append(stacks)
	return from_dictionary({"version": 1, "revision": warehouse.revision, "cabinets": rows})


## 用统一目录还原物品具体类型及所有成长状态，不允许超堆叠数量或非法柜内布局。
## [param catalog] 已完成规则加载的物品工厂。
## 返回可执行存取的领域仓库。
func materialize(catalog: ItemCatalog) -> DomainResult:
	var warehouse := PersonalWarehouse.new()
	warehouse.revision = _revision
	warehouse._cabinets.clear()
	for cabinet: Cabinet in _cabinets:
		var items: Array[GameItem] = []
		for stack: InventoryStackRecord in cabinet.stacks:
			var created := catalog.create(stack.item_definition_id, stack.item_state())
			if not created.is_ok: return created
			var item: GameItem = created.value
			if item.quantity != stack.quantity or item.quantity > item.max_stack:
				return DomainResult.failure(&"warehouse.quantity", "仓库存档物品数量无效")
			items.append(item)
		var inventory := Inventory.new()
		var restored := inventory.restore_items(items)
		if not restored.is_ok: return restored
		warehouse._cabinets.append(inventory)
	return DomainResult.ok(warehouse)


## 序列化只含原始事实的六柜记录。
## 返回JSON可写入的独立状态，不保存重复计算后的属性或图标。
func to_dictionary() -> Dictionary:
	var rows: Array = []
	for cabinet: Cabinet in _cabinets:
		var stacks: Array[Dictionary] = []
		for stack: InventoryStackRecord in cabinet.stacks: stacks.append(stack.to_dictionary())
		rows.append(stacks)
	return {"version": 1, "revision": _revision, "cabinets": rows}


## 创建延迟还原的领域仓库，普通人物事务不访问柜内物品。
## [param catalog] 实际存取时使用的目录。
## 返回拥有此只读快照的独立仓库实例。
func to_domain(catalog: ItemCatalog) -> DomainResult:
	return DomainResult.ok(StoredPersonalWarehouse.new(self, catalog))


## 读取仓库版本，供延迟领域对象校验存取意图。
## 返回存档记录中的整数版本。
func revision() -> int:
	return _revision


## 读取已开通柜数，不提供可改写的库存记录数组。
## 返回已开通柜数量。
func cabinet_count() -> int:
	return _cabinets.size()


## 只核对身份集合，不构造物品或对外暴露可变的存档记录。
## [param inventory_ids] 背包已经使用的身份。
## [param equipment_ids] 已装配物品身份。
## 返回跨容器身份校验结果。
func validate_disjoint(inventory_ids: Dictionary, equipment_ids: Dictionary) -> DomainResult:
	for cabinet: Cabinet in _cabinets:
		for stack: InventoryStackRecord in cabinet.stacks:
			if inventory_ids.has(stack.stack_id) or equipment_ids.has(stack.stack_id):
				return DomainResult.failure(&"warehouse.identity", "仓库物品与背包或装备身份重复")
	return DomainResult.ok()
