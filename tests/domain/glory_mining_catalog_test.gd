extends SceneTree

const MiningCatalogScript := preload("res://scripts/domain/mining/mining_catalog.gd")

var failures := PackedStringArray()
var assertions := 0


func _initialize() -> void:
	var loaded: Variant = MiningCatalogScript.load_default()
	_expect(loaded.is_ok, "荣耀矿物目录应加载")
	if not loaded.is_ok:
		_finish()
		return
	var catalog = loaded.value
	_expect(catalog.mineral_ids().size() == 35, "客户端确认的 35 类矿源应全部注册")
	_expect(catalog.map_ids().size() == 28, "27 张来源地图和 D04 新手回退图应启用矿源池")
	var secret: Dictionary = catalog.mineral("glory_mineral_82be09b62d86")
	_expect(not secret.is_empty(), "神秘宝藏矿源类应保留")
	_expect(not bool(secret.get("collectible", true)), "没有物品类的神秘宝藏不得进入普通采集结算")
	var iron: Dictionary = catalog.mineral("iron_ore")
	_expect(iron.get("required_mining_level") == 10, "铁矿应保留 10 级需求")
	_expect(not String(iron.get("description", "")).is_empty(), "矿物说明应保留")
	var source_maps := 0
	for map_id: String in catalog.map_ids():
		var policy: Dictionary = catalog.policy_for_map(map_id)
		if not policy.get("mineral_pool", []).is_empty():
			source_maps += 1
		for entry: Dictionary in policy.get("mineral_pool", []):
			_expect(not catalog.mineral(String(entry.get("mineral_id", ""))).is_empty(), "地图矿池不得悬空")
	_expect(source_maps == 28, "每条地图关系和新手回退图都应形成可用矿池")
	_finish()


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("GLORY_MINING_CATALOG_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
