class_name InventoryLayout
extends RefCounted


const MAIN_CONTAINER_ID := "main"
const MAIN_SIZE := Vector2i(276, 295)
const SNAP_SIZE := 1
const GRID_COLUMNS := 5
const GRID_ROWS := 8
const ITEM_LIMIT := GRID_COLUMNS * GRID_ROWS


## 校验背包容量、实例身份和坐标边界；不同物品可以使用相同坐标。
## [param items] 包含 position_px、container_id 与稳定实例标识的物品数组。
## 返回成功或容量、身份、坐标错误；旧 footprint_px 仅作为兼容元数据保留。
static func validate(items: Array) -> DomainResult:
	if items.size() > ITEM_LIMIT:
		return DomainResult.failure(&"inventory.capacity_exceeded", "inventory contains more than 40 items")
	var ids: Dictionary = {}
	for item: Variant in items:
		if not item is Dictionary:
			return DomainResult.failure(&"inventory.invalid_item", "inventory item must be a dictionary")
		var item_id := String(item.get("instance_id", item.get("stack_id", "")))
		if item_id.is_empty() or ids.has(item_id):
			return DomainResult.failure(&"inventory.duplicate_item", "inventory item identity is empty or duplicated")
		ids[item_id] = true
		if String(item.get("container_id", MAIN_CONTAINER_ID)) != MAIN_CONTAINER_ID:
			return DomainResult.failure(&"inventory.invalid_container", "only the main inventory container is currently enabled")
		var position := _vector(item.get("position_px", []), Vector2i(-1, -1))
		if position.x < 0 or position.y < 0 or position.x >= MAIN_SIZE.x or position.y >= MAIN_SIZE.y:
			return DomainResult.failure(&"inventory.out_of_bounds", "inventory position exceeds the main container")
	return DomainResult.ok()


## 只修改目标物品的坐标，不吸附、不挤开其他物品、不拒绝重叠。
## [param items] 当前权威物品布局。
## [param instance_id] 待移动的稳定物品实例标识。
## [param requested_position] 容器局部像素坐标。
## 返回布局副本，失败保持输入不变。
static func move_item(items: Array, instance_id: String, requested_position: Vector2i) -> DomainResult:
	var candidate: Array = items.duplicate(true)
	var found := false
	for item: Dictionary in candidate:
		if String(item.get("instance_id", item.get("stack_id", ""))) != instance_id:
			continue
		if bool(item.get("locked", false)):
			return DomainResult.failure(&"inventory.item_locked", "locked inventory item cannot be moved")
		item["position_px"] = [requested_position.x, requested_position.y]
		found = true
		break
	if not found:
		return DomainResult.failure(&"inventory.item_not_found", "inventory item does not exist")
	var validation := validate(candidate)
	return DomainResult.ok(candidate) if validation.is_ok else validation


## 仅在用户点整理时，按稳定实例标识将物品坐标对齐到五列八行虚拟网格。
## [param items] 当前自由坐标布局。
## 返回完整的新布局，不改变物品身份、数量和其他状态。
static func arrange(items: Array) -> DomainResult:
	var validation := validate(items)
	if not validation.is_ok:
		return validation
	var pending: Array = items.duplicate(true)
	pending.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("instance_id", left.get("stack_id", ""))) \
			< String(right.get("instance_id", right.get("stack_id", "")))
	)
	for index: int in pending.size():
		var position := grid_position(index)
		pending[index]["position_px"] = [position.x, position.y]
	return DomainResult.ok(pending)


## 为新入包物品优先选择未被其他图标盖住的虚拟格子，不重排已有物品。
## [param items] 当前背包布局。
## [param _footprint] 保留旧调用签名；图标尺寸不再影响容量或落位合法性。
## 返回推荐坐标；只有达到物品数量上限时返回 (-1,-1)。
static func first_available_position(items: Array, _footprint: Vector2i) -> Vector2i:
	if items.size() >= ITEM_LIMIT:
		return Vector2i(-1, -1)
	var cell_size := (Vector2(MAIN_SIZE) / Vector2(GRID_COLUMNS, GRID_ROWS)).floor()
	for index: int in ITEM_LIMIT:
		var candidate := grid_position(index)
		var obscured := false
		for item: Dictionary in items:
			var position := _vector(item.get("position_px", []), Vector2i(-1, -1))
			if Rect2(Vector2(candidate), cell_size).intersects(Rect2(Vector2(position), cell_size)):
				obscured = true
				break
		if not obscured:
			return candidate
	# 自由摆放可能覆盖所有虚拟格子，但只要未满四十件，就仍然允许入包。
	return grid_position(items.size())


## 返回虚拟格子的左上角整数坐标，只供整理和新物品默认落位使用。
## [param index] 范围为 0..39 的格子索引。
## 返回与 UI 五列八行划分一致的坐标。
static func grid_position(index: int) -> Vector2i:
	return Vector2i(
		floori(float(index % GRID_COLUMNS) * MAIN_SIZE.x / GRID_COLUMNS),
		floori(floorf(float(index) / GRID_COLUMNS) * MAIN_SIZE.y / GRID_ROWS),
	)


## 将二元素数组安全转换为整数向量。
## [param value] 待转换值。
## [param fallback] 无效输入时使用的默认值。
## 返回转换后的 Vector2i。
static func _vector(value: Variant, fallback: Vector2i) -> Vector2i:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback
