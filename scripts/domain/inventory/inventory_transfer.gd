class_name InventoryTransfer
extends RefCounted

class Merge extends RefCounted:
	var target: GameItem
	var amount: int


## 预检两个独立容器之间的完整存取，合并多个余量堆叠后一次提交。
## [param source] 当前拥有物品的容器。
## [param target] 接收物品的容器。
## [param id] 来源实例身份。
## [param amount] 本次正整数数量，不超过原堆叠。
## [param split_id] 只有部分存取才使用的服务端新身份。
## 返回实际转移数量；失败不修改任何对象，整件存取保留全部实例状态。
static func move(source: Inventory, target: Inventory, id: String, amount: int, split_id: String) -> DomainResult:
	if source == null or target == null or source == target:
		return DomainResult.failure(&"warehouse.container", "存取容器无效")
	var item := source.find(id)
	if item == null or item.locked:
		return DomainResult.failure(&"warehouse.item", "物品不存在或已锁定，请先解锁")
	if amount <= 0 or amount > item.quantity or amount > item.max_stack:
		return DomainResult.failure(&"warehouse.quantity", "请输入有效的存取数量")
	var whole := amount == item.quantity
	var new_id := id if whole else split_id
	if new_id.is_empty() or target.find(new_id) != null or (not whole and source.find(new_id) != null):
		return DomainResult.failure(&"warehouse.identity", "存取物品身份重复")
	var merges: Array[Merge] = []
	var remaining := amount
	for existing: GameItem in target.items():
		if not existing.can_stack_with(item): continue
		var moved := mini(existing.max_stack - existing.quantity, remaining)
		if moved <= 0: continue
		var merge := Merge.new()
		merge.target = existing
		merge.amount = moved
		merges.append(merge)
		remaining -= moved
		if remaining == 0: break
	var position := Vector2i.ZERO
	if remaining > 0:
		var space := target.transfer_position(item)
		if not space.is_ok: return space
		position = space.value
	# 从这里开始没有外部回调和可失败分支；不通过先扣物品再尝试入账来试容量。
	var incoming: GameItem = item if whole else item.copy_stack(new_id, amount)
	if whole:
		source.remove_for_transfer(id)
	else:
		item.quantity -= amount
	for merge: Merge in merges: merge.target.quantity += merge.amount
	if remaining > 0:
		incoming.quantity = remaining
		incoming.container_id = InventoryLayout.MAIN_CONTAINER_ID
		incoming.position_px = position
		target._items.append(incoming)
	source.commit_transfer()
	target.commit_transfer()
	return DomainResult.ok({"quantity": amount, "instance_id": new_id})
