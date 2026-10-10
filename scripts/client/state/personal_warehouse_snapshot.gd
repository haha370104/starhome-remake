class_name PersonalWarehouseSnapshot
extends RefCounted

var revision := -1
var cabinet := 1
var cabinet_count := 1
var maximum_cabinets := 6
var expansion_cost := 0
var available := false
var inventory: Inventory
var _views: Dictionary[String, Dictionary] = {}


static func from_payload(raw: Dictionary, player: CurrentPlayer, previous: PersonalWarehouseSnapshot) -> DomainResult:
	var snapshot := PersonalWarehouseSnapshot.new()
	snapshot.revision = int(raw.revision)
	snapshot.cabinet = int(raw.cabinet)
	snapshot.cabinet_count = int(raw.cabinet_count)
	snapshot.maximum_cabinets = int(raw.maximum_cabinets)
	snapshot.available = bool(raw.available)
	snapshot.expansion_cost = int(raw.expansion_cost)
	snapshot.inventory = Inventory.new(int(raw.capacity), snapshot.revision)
	var items: Array[GameItem] = []
	for view: Dictionary in raw.items:
		var identity := String(view.instance_id)
		var item: GameItem
		if previous != null and previous.cabinet == snapshot.cabinet and previous._views.get(identity) == view:
			item = previous.inventory.find(identity)
		else:
			var created := player.create_inventory_item(view)
			if not created.is_ok: return created
			item = created.value
		items.append(item)
		snapshot._views[identity] = view
	var checked := snapshot.inventory.restore_items(items)
	return DomainResult.ok(snapshot) if checked.is_ok else checked
