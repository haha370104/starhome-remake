class_name PersonalWarehouseSnapshot
extends RefCounted

class ItemRow extends RefCounted:
	var id := ""
	var title := ""
	var description := ""
	var quantity := 0
	var locked := false
	var bound := false
	var presentation: Dictionary = {}

	## 将安全物品投影转换为仓库列表行，不用于还原或保存实际物品。
	## [param view] 权威物品显示字段。
	## 返回具名的只读展示数据。
	static func from_view(view: Dictionary) -> ItemRow:
		var row := ItemRow.new()
		row.id = String(view.get("instance_id", ""))
		row.title = String(view.get("display_name", ""))
		row.description = String(view.get("description", ""))
		row.quantity = maxi(0, int(view.get("amount", 0)))
		row.locked = bool(view.get("locked", false))
		row.bound = bool(view.get("bound", false))
		row.presentation = view.get("presentation", {}).duplicate(true)
		return row

	## 拼接列表中可直接区分的数量、锁定和绑定信息。
	## 返回统一显示文字。
	func label() -> String:
		return "%s%s%s ×%d" % ["[锁定] " if locked else "", "[绑定] " if bound else "", title, quantity]

var revision := -1
var inventory_revision := -1
var cabinet := 1
var cabinet_count := 1
var maximum_cabinets := 6
var capacity := 40
var inventory_capacity := 40
var expansion_cost := 0
var amethyst := 0
var available := false
var message := ""
var stored: Array[ItemRow] = []
var carried: Array[ItemRow] = []


## 在UI入口转换仓库快照，背包复用已还原的当前玩家库存。
## [param raw] 当前柜的服务端投影。
## [param inventory] 与本条消息同事务的客户端只读背包。
## 返回供仓库窗口使用的类型化快照。
static func from_payload(raw: Dictionary, inventory: Inventory) -> PersonalWarehouseSnapshot:
	var snapshot := PersonalWarehouseSnapshot.new()
	snapshot.revision = int(raw.get("revision", -1))
	snapshot.inventory_revision = int(raw.get("inventory_revision", -1))
	snapshot.cabinet_count = clampi(int(raw.get("cabinet_count", 1)), 1, 6)
	snapshot.cabinet = clampi(int(raw.get("cabinet", 1)), 1, snapshot.cabinet_count)
	snapshot.maximum_cabinets = clampi(int(raw.get("maximum_cabinets", 6)), 1, 6)
	snapshot.capacity = maxi(0, int(raw.get("capacity", 0)))
	snapshot.available = bool(raw.get("available", false))
	snapshot.expansion_cost = maxi(0, int(raw.get("expansion_cost", 0)))
	snapshot.amethyst = maxi(0, int(raw.get("amethyst", 0)))
	snapshot.message = String(raw.get("message", ""))
	for view: Dictionary in raw.get("items", []):
		snapshot.stored.append(ItemRow.from_view(view))
	if inventory != null and inventory.revision == snapshot.inventory_revision:
		snapshot.inventory_capacity = inventory.capacity
		for item: GameItem in inventory.items():
			var view := item.to_view_dictionary()
			view["presentation"] = item.presentation_for("inventory")
			snapshot.carried.append(ItemRow.from_view(view))
	else:
		snapshot.available = false
		snapshot.message = "背包与仓库状态不同步，请刷新"
	return snapshot
