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


## 将同类兼容堆叠尽量合入选中物品，保留剩余数量和所有不兼容实例。
## [param inventory] 背包所有者。
## [param id] 接收合并数量的目标实例。
## [param expected_revision] 客户端背包版本。
## 返回实际合并数量；无可合并内容时不推进版本。
static func merge(inventory: Inventory, id: String, expected_revision: int) -> DomainResult:
	var checked := inventory.require_revision(expected_revision)
	if not checked.is_ok:
		return checked
	var target := inventory.find(id)
	if target == null or target.locked or target.max_stack <= 1:
		return DomainResult.failure(&"inventory.invalid_merge", "该物品不能合并")
	var moved := 0
	for other: GameItem in inventory.items():
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
