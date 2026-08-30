extends SceneTree

const RegistryScript := preload(
	"res://scripts/domain/content/known_content_registry.gd"
)
const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")

var assertions := 0
var failures: Array[String] = []


## 初始化对象及其运行时依赖。
func _init() -> void:
	_run()


## 验证全量来源覆盖、运行时映射、跨表地图关系和重复旧类名查询。
func _run() -> void:
	var loaded := RegistryScript.load_default()
	_expect(loaded.is_ok, "known-content registry should load")
	if not loaded.is_ok:
		push_error(loaded.error_message)
		_finish()
		return
	var registry = loaded.value
	_expect(registry.summary_for(&"map").get("definitions") == 814, "all 814 map keys")
	_expect(registry.summary_for(&"monster").get("npc_rows") == 119, "all 119 NPC rows")
	_expect(
		registry.summary_for(&"monster").get("map_archetypes") == 20,
		"all 20 monster map archetypes",
	)
	_expect(
		registry.summary_for(&"monster").get("monster_map_relations") == 85,
		"all 85 monster-map relations",
	)
	_expect(
		registry.summary_for(&"item").get("equipment_rows") == 1012,
		"all 1012 recovered equipment rows",
	)
	_expect(
		registry.summary_for(&"map").get("runtime_ready_source_keys") == 810,
		"all 810 packaged map sources should be runtime-ready",
	)
	_expect(registry.summary_for(&"monster").get("runtime_ready_npc_rows") == 119, "all NPC rows should be runtime-ready")
	_expect(
		registry.summary_for(&"item").get("runtime_item_ids") == 1284,
		"all generated and curated runtime item IDs should be represented",
	)
	_expect(registry.size() == 2349, "source catalogs plus three explicit remake definitions should total 2349")
	_expect(
		registry.registrations_for_runtime(&"map", "buli_c03_field_zone").size() == 1,
		"promoted Buli C03 should be represented by its NFT_BL source registration",
	)

	var d04_sources: Array[Dictionary] = registry.registrations_for_runtime(
		&"map", "d04_field_zone"
	)
	_expect(d04_sources.size() == 1, "semantic NFT_BL D04 source should retain the curated runtime map")
	_expect(
		_all_runtime_ready(d04_sources),
		"runtime map sources must be explicitly ready",
	)
	var g08: Dictionary = registry.definition("map:nft_bl/g08")
	_expect(g08.get("availability", {}).get("presentation") == "partial", "G08 remains partial")

	var om_adult: Array[Dictionary] = registry.registrations_for_runtime(
		&"monster", "om_adult"
	)
	_expect(om_adult.size() == 1, "runtime adult Om maps to one recovered NPC row")
	_expect(om_adult[0].get("source_index") == 4, "adult Om retains source NPC index 4")
	var light_ball_classes: Array[Dictionary] = registry.registrations_for_legacy_key(
		&"monster", "class:NpcLightBall1"
	)
	_expect(light_ball_classes.size() == 1, "photosensitive map class is registered")
	if not light_ball_classes.is_empty():
		var presence: Array = light_ball_classes[0].get("map_presence", [])
		_expect(
			_presence_has_map(presence, "map:nft_bl/e07"),
			"photosensitive class retains its E07 map relation",
		)

	var gun_rows: Array[Dictionary] = registry.registrations_for_legacy_key(
		&"item", "class:gun1"
	)
	_expect(not gun_rows.is_empty(), "gun1 equipment class should be queryable")
	_expect(
		_registrations_contain_runtime(gun_rows, "recruit_energy_cannon"),
		"gun1 should map to the runtime recruit energy cannon",
	)
	var iron_rows: Array[Dictionary] = registry.registrations_for_legacy_key(
		&"item", "name:铁矿"
	)
	_expect(
		_registrations_contain_runtime(iron_rows, "iron_ore"),
		"recovered iron material should map to the runtime ore definition",
	)

	var item_catalog: ItemCatalog = ItemCatalogScript.new()
	var item_loaded := item_catalog.initialize()
	_expect(item_loaded.is_ok, "current runtime item catalog should still initialize")
	_expect(item_catalog.definition_ids().size() == 1284, "runtime item catalog should expose 1284 definitions")
	for runtime_id: String in item_catalog.definition_ids():
		_expect(
			not registry.registrations_for_runtime(&"item", runtime_id).is_empty(),
			"runtime item must have known registration: %s" % runtime_id,
		)
	_finish()


## 执行 `all_runtime_ready` 对应的模块操作。
## [param definitions] 调用方传入的 `definitions` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _all_runtime_ready(definitions: Array[Dictionary]) -> bool:
	for definition: Dictionary in definitions:
		if definition.get("availability", {}).get("runtime") != "ready":
			return false
	return true


## 执行 `presence_has_map` 对应的模块操作。
## [param presence] 调用方传入的 `presence` 参数。
## [param map_id] 调用方传入的 `map_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _presence_has_map(presence: Array, map_id: String) -> bool:
	for value: Variant in presence:
		if value is Dictionary and value.get("map_id") == map_id:
			return true
	return false


## 执行 `registrations_contain_runtime` 对应的模块操作。
## [param definitions] 调用方传入的 `definitions` 参数。
## [param runtime_id] 调用方传入的 `runtime_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _registrations_contain_runtime(definitions: Array[Dictionary], runtime_id: String) -> bool:
	for definition: Dictionary in definitions:
		if (definition.get("runtime_ids", []) as Array).has(runtime_id):
			return true
	return false


## 记录一项测试断言及其失败信息。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 汇总测试断言并以对应退出码结束测试。
func _finish() -> void:
	if failures.is_empty():
		print("KNOWN_CONTENT_REGISTRY_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("KNOWN_CONTENT_REGISTRY_FAILED (%d assertions, %d failures)" % [
		assertions, failures.size(),
	])
	quit(1)
