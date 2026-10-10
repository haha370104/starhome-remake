class_name InventoryStackActions
extends RefCounted


## 预检数量、容量和版本后拆分堆叠，失败不改变任何数量。
## [param inventory] 拥有物品和布局的背包。
## [param id] 原堆叠实例标识。
## [param amount] 拆出数量，必须小于原数量。
## [param expected_revision] 客户端背包版本。
## 返回新堆叠标识或领域错误。
static func split(inventory: Inventory, id: String, amount: int, expected_revision: int) -> DomainResult:
	var checked := inventory.require_revision(expected_revision)
	if not checked.is_ok:
		return checked
	var item := inventory.find(id)
	if item == null or item.locked or item.max_stack <= 1 or amount <= 0 or amount >= item.quantity:
		return DomainResult.failure(&"inventory.invalid_split", "该物品不能拆分或拆分数量无效")
	var new_id := "%s.split.%s" % [id, Crypto.new().generate_random_bytes(16).hex_encode()]
	var copy := item.copy_stack(new_id, amount)
	var added := inventory.add_from_transfer(copy)
	if not added.is_ok:
		return added
	item.quantity -= amount
	inventory.commit_transfer()
	return DomainResult.ok(new_id)


## 将兼容堆叠合入目标；指定 target_id 时只移动选定源堆叠，否则自动归并同类堆叠。
## [param inventory] 背包所有者。
## [param id] 指定 target_id 时为源实例，否则为接收数量的目标实例。
## [param expected_revision] 客户端背包版本。
## [param target_id] 可选的定向合并目标。
## 返回实际合并数量；无可合并内容时不推进版本。
static func merge(
	inventory: Inventory,
	id: String,
	expected_revision: int,
	target_id: String = "",
) -> DomainResult:
	var checked := inventory.require_revision(expected_revision)
	if not checked.is_ok:
		return checked
	var target := inventory.find(id if target_id.is_empty() else target_id)
	if target == null or target.locked or target.max_stack <= 1:
		return DomainResult.failure(&"inventory.invalid_merge", "该物品不能合并")
	var sources: Array[GameItem] = inventory.items()
	if not target_id.is_empty():
		var source := inventory.find(id)
		if source == null or not target.can_stack_with(source):
			return DomainResult.failure(&"inventory.invalid_merge", "源物品和目标物品不能合并")
		sources = [source]
	var moved := 0
	for other: GameItem in sources:
		if not target.can_stack_with(other):
			continue
		var amount := mini(other.quantity, target.max_stack - target.quantity)
		if amount <= 0:
			break
		other.quantity -= amount
		target.quantity += amount
		moved += amount
		if other.quantity == 0:
			inventory.remove_for_transfer(other.instance_id)
	if moved == 0:
		return DomainResult.failure(&"inventory.nothing_to_merge", "没有可合并的同类堆叠，或当前堆叠已满")
	inventory.commit_transfer()
	return DomainResult.ok(moved)
