class_name Inventory
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const InventoryLayoutScript := preload("res://scripts/domain/inventory/inventory_layout.gd")

var capacity: int
var revision: int
var currency: int
var _items: Array[GameItem] = []


## 初始化拥有容量、货币与独立乐观锁版本的背包。
## [param initial_capacity] 最大物品实例数量。
## [param initial_revision] 当前背包 revision。
## [param initial_currency] 当前货币数量。
func _init(
	initial_capacity: int = InventoryLayoutScript.ITEM_LIMIT,
	initial_revision: int = 0,
	initial_currency: int = 0,
) -> void:
	capacity = maxi(1, initial_capacity)
	revision = maxi(0, initial_revision)
	currency = maxi(0, initial_currency)


## 装载来自可信映射边界的物品，并验证整体布局。
## [param loaded_items] 已从配置目录还原类型的物品实例。
## 返回成功或布局、容量错误。
func restore_items(loaded_items: Array[GameItem]) -> DomainResult:
	if loaded_items.size() > capacity:
		return DomainResult.failure(&"inventory.capacity_exceeded", "inventory exceeds configured capacity")
	_items = loaded_items.duplicate()
	return InventoryLayoutScript.validate(layout_items())


## 查询物品实例，但不暴露内部数组的可变引用。
## 返回按当前布局顺序排列的浅副本。
func items() -> Array[GameItem]:
	return _items.duplicate()


## 按稳定实例标识查询物品。
## [param instance_id] 物品实例标识。
## 返回物品；不存在时返回 null。
func find(instance_id: String) -> GameItem:
	for item: GameItem in _items:
		if item.instance_id == instance_id:
			return item
	return null


## 校验 revision 后移动物品并推进背包版本。
## [param instance_id] 待移动物品实例标识。
## [param requested_position] 请求的容器局部像素坐标。
## [param expected_revision] 客户端读取到的背包 revision。
## 返回成功或版本、锁定、越界、重叠错误。
func move_item(
	instance_id: String,
	requested_position: Vector2i,
	expected_revision: int,
) -> DomainResult:
	var revision_result := require_revision(expected_revision)
	if not revision_result.is_ok:
		return revision_result
	var moved := InventoryLayoutScript.move_item(layout_items(), instance_id, requested_position)
	if not moved.is_ok:
		return moved
	_apply_layouts(moved.value)
	revision += 1
	return DomainResult.ok()


## 校验 revision 后紧凑排列所有背包物品。
## [param expected_revision] 客户端读取到的背包 revision。
## 返回成功或版本、容量错误。
func arrange(expected_revision: int) -> DomainResult:
	var revision_result := require_revision(expected_revision)
	if not revision_result.is_ok:
		return revision_result
	var arranged := InventoryLayoutScript.arrange(layout_items())
	if not arranged.is_ok:
		return arranged
	_apply_layouts(arranged.value)
	revision += 1
	return DomainResult.ok()


## 为聚合内装备转移移除指定物品，不单独推进 revision。
## [param instance_id] 待移除物品实例标识。
## 返回被移除物品或不存在、锁定错误。
## 设计：该方法只供 Player 的原子换装流程调用，revision 由完整事务统一推进。
func remove_for_transfer(instance_id: String) -> DomainResult:
	for index in _items.size():
		var item: GameItem = _items[index]
		if item.instance_id != instance_id:
			continue
		if item.locked:
			return DomainResult.failure(&"inventory.item_locked", "locked inventory item cannot be equipped")
		_items.remove_at(index)
		return DomainResult.ok(item)
	return DomainResult.failure(&"inventory.item_not_found", "inventory item does not exist")


## 为聚合内装备转移寻找位置并放回物品，不单独推进 revision。
## [param item] 待放回背包的物品实例。
## 返回成功或容量、空间错误。
## 设计：该方法与 remove_for_transfer 配对，由 Player 保证整个换装命令的事务边界。
func add_from_transfer(item: GameItem) -> DomainResult:
	var position_result := transfer_position(item)
	if not position_result.is_ok:
		return position_result
	item.container_id = InventoryLayoutScript.MAIN_CONTAINER_ID
	item.position_px = position_result.value
	_items.append(item)
	return DomainResult.ok()


## 将权威奖励物品合并到已有堆叠或放入首个可用背包位置。
## [param item] 已由受控物品目录创建且带唯一实例标识的奖励物品。
## 返回合并后的实例或容量、布局、数量错误。
## 设计：一次调用要么完整接收数量并推进 revision，要么完全不修改背包。
func add_reward(item: GameItem) -> DomainResult:
	if item == null or item.instance_id.is_empty() or item.quantity <= 0 \
		or item.quantity > item.max_stack:
		return DomainResult.failure(&"inventory.invalid_reward", "reward item identity or quantity is invalid")
	if find(item.instance_id) != null:
		return DomainResult.failure(&"inventory.duplicate_item", "reward item identity already exists")
	for current: GameItem in _items:
		if current.definition_id != item.definition_id or current.bound != item.bound \
			or current.locked or current.quantity + item.quantity > current.max_stack:
			continue
		current.quantity += item.quantity
		revision += 1
		return DomainResult.ok(current)
	var position_result := transfer_position(item)
	if not position_result.is_ok:
		return position_result
	item.container_id = InventoryLayoutScript.MAIN_CONTAINER_ID
	item.position_px = position_result.value
	_items.append(item)
	revision += 1
	return DomainResult.ok(item)


## 预检一次装备转移后可使用的背包位置。
## [param item] 即将放入背包的物品。
## [param excluding_instance_id] 同一事务中将先移出的背包物品标识。
## 返回可用位置或容量、空间错误。
func transfer_position(item: GameItem, excluding_instance_id: String = "") -> DomainResult:
	if item == null:
		return DomainResult.failure(&"inventory.no_space", "inventory transfer item is missing")
	var layouts: Array[Dictionary] = []
	var retained_count := 0
	for current: GameItem in _items:
		if current.instance_id == excluding_instance_id:
			continue
		retained_count += 1
		layouts.append(current.to_layout_dictionary())
	if retained_count >= capacity:
		return DomainResult.failure(&"inventory.no_space", "inventory has no room for equipment")
	var position := InventoryLayoutScript.first_available_position(layouts, item.footprint_px)
	if position.x < 0:
		return DomainResult.failure(&"inventory.no_space", "inventory has no rectangle large enough for equipment")
	return DomainResult.ok(position)


## 推进一次由玩家聚合完成的背包事务版本。
func commit_transfer() -> void:
	revision += 1


## 校验客户端背包 revision。
## [param expected_revision] 客户端命令携带的 revision。
## 返回成功或版本冲突。
func require_revision(expected_revision: int) -> DomainResult:
	if expected_revision != revision:
		return DomainResult.failure(&"inventory.revision_conflict", "inventory revision changed")
	return DomainResult.ok()


## 导出共享布局器需要的物品字典数组。
## 返回不包含业务数值的布局记录。
func layout_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: GameItem in _items:
		result.append(item.to_layout_dictionary())
	return result


## 将布局器返回的位置写回对应物品。
## [param layouts] 已校验的布局记录数组。
func _apply_layouts(layouts: Array) -> void:
	var by_id: Dictionary = {}
	for layout: Dictionary in layouts:
		by_id[String(layout.get("instance_id", ""))] = layout
	for item: GameItem in _items:
		if by_id.has(item.instance_id):
			item.apply_layout(by_id[item.instance_id])
