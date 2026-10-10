class_name InventoryTransfer
extends RefCounted

## 预检两个独立容器之间的整堆存取，按指定落点一次提交。
## [param source] 当前拥有物品的容器。
## [param target] 接收物品的容器。
## [param id] 来源实例身份。
## [param position] 目标容器内的物品中心坐标。
## 返回实际转移数量；失败不修改任何对象，整件存取保留全部实例状态。
static func move(source: Inventory, target: Inventory, id: String, position: Vector2i) -> DomainResult:
	if source == null or target == null or source == target:
		return DomainResult.failure(&"warehouse.container", "存取容器无效")
	var item := source.find(id)
	if item == null or item.locked:
		return DomainResult.failure(&"warehouse.item", "物品不存在或已锁定，请先解锁")
	if target.find(id) != null:
		return DomainResult.failure(&"warehouse.identity", "存取物品身份重复")
	if target._items.size() >= target.capacity:
		return DomainResult.failure(&"inventory.no_space", "目标容器已满")
	if not Rect2i(Vector2i.ZERO, InventoryLayout.MAIN_SIZE).has_point(position):
		return DomainResult.failure(&"warehouse.position", "物品位置超出容器")
	source.remove_for_transfer(id)
	item.container_id = InventoryLayout.MAIN_CONTAINER_ID
	item.position_px = position
	target._items.append(item)
	source.commit_transfer()
	target.commit_transfer()
	return DomainResult.ok({"quantity": item.quantity, "instance_id": id})
