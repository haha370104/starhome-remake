class_name InventoryLayout
extends RefCounted


const MAIN_CONTAINER_ID := "main"
const MAIN_SIZE := Vector2i(276, 295)
const SNAP_SIZE := 15
const ITEM_LIMIT := 40


## 校验整份像素背包布局，保证所有物品位于容器内且互不重叠。
## [param items] 包含 position_px、footprint_px 与 container_id 的物品字典数组。
## 返回成功结果或首个可解释的布局错误。
## 设计：客户端可用本函数绘制拖动预览，权威服务器必须对命令结果再次执行同一规则。
static func validate(items: Array) -> DomainResult:
	if items.size() > ITEM_LIMIT:
		return DomainResult.failure(&"inventory.capacity_exceeded", "inventory contains more than 40 items")
	var ids: Dictionary = {}
	for item_index in items.size():
		var item: Variant = items[item_index]
		if not item is Dictionary:
			return DomainResult.failure(&"inventory.invalid_item", "inventory item must be a dictionary")
		var item_id := String(item.get("instance_id", item.get("stack_id", "")))
		if item_id.is_empty() or ids.has(item_id):
			return DomainResult.failure(&"inventory.duplicate_item", "inventory item identity is empty or duplicated")
		ids[item_id] = true
		var geometry := _geometry(item)
		if not geometry.is_ok:
			return geometry
		var item_rect: Rect2i = geometry.value
		for prior_index in item_index:
			var prior_geometry := _geometry(items[prior_index])
			if prior_geometry.is_ok and item_rect.intersects(prior_geometry.value):
				return DomainResult.failure(&"inventory.overlap", "inventory items overlap")
	return DomainResult.ok()


## 将物品移动到新的网格像素点，并返回不修改输入数组的布局副本。
## [param items] 当前权威物品布局。
## [param instance_id] 待移动的稳定物品实例标识。
## [param requested_position] 客户端请求的容器局部像素坐标。
## 返回包含新布局的成功结果，或锁定、越界、重叠等错误。
static func move_item(items: Array, instance_id: String, requested_position: Vector2i) -> DomainResult:
	var candidate: Array = items.duplicate(true)
	var found := false
	for item: Dictionary in candidate:
		if String(item.get("instance_id", item.get("stack_id", ""))) != instance_id:
			continue
		if bool(item.get("locked", false)):
			return DomainResult.failure(&"inventory.item_locked", "locked inventory item cannot be moved")
		item["position_px"] = [
			snappedi(requested_position.x, SNAP_SIZE),
			snappedi(requested_position.y, SNAP_SIZE),
		]
		found = true
		break
	if not found:
		return DomainResult.failure(&"inventory.item_not_found", "inventory item does not exist")
	var validation := validate(candidate)
	return DomainResult.ok(candidate) if validation.is_ok else validation


## 按稳定实例标识重新紧凑排列主背包。
## [param items] 当前物品布局。
## 返回完整的新布局；无法容纳时返回容量错误。
static func arrange(items: Array) -> DomainResult:
	var pending: Array = items.duplicate(true)
	pending.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("instance_id", left.get("stack_id", ""))) \
			< String(right.get("instance_id", right.get("stack_id", "")))
	)
	var placed: Array = []
	for item: Dictionary in pending:
		var footprint := _vector(item.get("footprint_px", [30, 30]), Vector2i(30, 30))
		var position := _first_available_position(placed, footprint)
		if position.x < 0:
			return DomainResult.failure(&"inventory.no_space", "inventory has no rectangle large enough for the item")
		item["container_id"] = MAIN_CONTAINER_ID
		item["position_px"] = [position.x, position.y]
		placed.append(item)
	return DomainResult.ok(placed)


## 查找可放置给定尺寸物品的首个网格位置。
## [param items] 已占用布局。
## [param footprint] 待放置物品像素尺寸。
## 返回可用坐标；不存在时返回 (-1,-1)。
static func first_available_position(items: Array, footprint: Vector2i) -> Vector2i:
	return _first_available_position(items, footprint)


## 解析并校验一个物品的矩形几何。
## [param item] 待解析物品字典。
## 返回 Rect2i 或领域错误。
static func _geometry(item: Dictionary) -> DomainResult:
	if String(item.get("container_id", MAIN_CONTAINER_ID)) != MAIN_CONTAINER_ID:
		return DomainResult.failure(&"inventory.invalid_container", "only the main inventory container is currently enabled")
	var position := _vector(item.get("position_px", []), Vector2i(-1, -1))
	var footprint := _vector(item.get("footprint_px", []), Vector2i.ZERO)
	if position.x < 0 or position.y < 0 or footprint.x <= 0 or footprint.y <= 0:
		return DomainResult.failure(&"inventory.invalid_geometry", "inventory geometry is invalid")
	var rectangle := Rect2i(position, footprint)
	if rectangle.end.x > MAIN_SIZE.x or rectangle.end.y > MAIN_SIZE.y:
		return DomainResult.failure(&"inventory.out_of_bounds", "inventory item exceeds the main container")
	return DomainResult.ok(rectangle)


## 扫描主容器中的首个可用网格位置。
## [param items] 已放置物品数组。
## [param footprint] 待放置物品尺寸。
## 返回可用位置或 (-1,-1)。
static func _first_available_position(items: Array, footprint: Vector2i) -> Vector2i:
	for y in range(0, MAIN_SIZE.y - footprint.y + 1, SNAP_SIZE):
		for x in range(0, MAIN_SIZE.x - footprint.x + 1, SNAP_SIZE):
			var candidate := Rect2i(Vector2i(x, y), footprint)
			var blocked := false
			for item: Dictionary in items:
				var geometry := _geometry(item)
				if geometry.is_ok and candidate.intersects(geometry.value):
					blocked = true
					break
			if not blocked:
				return candidate.position
	return Vector2i(-1, -1)


## 将二元素数组安全转换为整数向量。
## [param value] 待转换值。
## [param fallback] 无效输入时使用的默认值。
## 返回转换后的 Vector2i。
static func _vector(value: Variant, fallback: Vector2i) -> Vector2i:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback
