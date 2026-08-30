extends SceneTree

const MiningCatalogScript := preload("res://scripts/domain/mining/mining_catalog.gd")
const MiningModuleScript := preload(
	"res://scripts/server/modules/mining/authoritative_mining_module.gd"
)

class FakeNavigation:
	extends RefCounted
	var graph := AStar2D.new()

var failures: Array[String] = []
var assertions := 0


## 执行本测试脚本的全部验证并汇总结果。
func _initialize() -> void:
	_test_catalog_and_initial_population()
	_test_three_second_collection_and_capacity()
	_test_five_minute_replenishment()
	if failures.is_empty():
		print("AUTHORITATIVE_MINING_MODULE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 验证 `test_catalog_and_initial_population` 对应的业务约束。
func _test_catalog_and_initial_population() -> void:
	var catalog_result := MiningCatalogScript.load_default()
	_expect(catalog_result.is_ok, "default mining catalog should load")
	if not catalog_result.is_ok:
		return
	var module = _module(catalog_result.value, "d04_field_zone", "d04.instance.test")
	_expect(module.sources.size() == 20, "each enabled map should start with twenty mine sources")
	for source in module.sources.values():
		_expect(source.capacity == 50 and source.remaining == 50, "every new mine source should contain fifty units")
		_expect(source.mineral_id == "iron_ore", "D04 beginner pool should currently contain iron")
	var disabled = _module(catalog_result.value, "yian_harbor_city", "city.instance.test")
	_expect(disabled.sources.is_empty(), "non-field city maps should not grow mine sources")


## 验证 `test_three_second_collection_and_capacity` 对应的业务约束。
func _test_three_second_collection_and_capacity() -> void:
	var catalog = MiningCatalogScript.load_default().value
	var module = _module(catalog, "d04_field_zone", "d04.collection.test")
	var source = module.sources.values()[0]
	var actor_position: Vector2 = source.position + Vector2(40.0, 0.0)
	var started: Variant = module.begin_collection("player.1", actor_position, source.position, 10, 1)
	_expect(started.is_ok and float(started.value["interval_seconds"]) == 3.0, "eligible actor should begin a three-second cycle")
	module.advance_ticks(59)
	_expect(module.drain_ready_cycles().is_empty(), "collection must not settle before three seconds at 20 Hz")
	module.advance_ticks(1)
	var ready: Array = module.drain_ready_cycles()
	_expect(ready.size() == 1, "exactly one collection cycle should become ready at three seconds")
	var committed: Variant = module.commit_cycle(String(ready[0]["token"]))
	_expect(committed.is_ok and int(committed.value["remaining"]) == 49, "successful cycle should remove exactly one of fifty minerals")
	_expect(not bool(committed.value["depleted"]), "partially consumed mine should remain in the map")
	_expect(not module.begin_collection("player.low", actor_position, source.position, 9, 1).is_ok, "mining level below the ore requirement should be rejected")
	_expect(not module.begin_collection("player.far", source.position + Vector2(80, 0), source.position, 10, 1).is_ok, "actor beyond seventy pixels should be rejected")


## 验证 `test_five_minute_replenishment` 对应的业务约束。
func _test_five_minute_replenishment() -> void:
	var catalog = MiningCatalogScript.load_default().value
	var module = _module(catalog, "d04_field_zone", "d04.replenish.test")
	var source = module.sources.values()[0]
	source.remaining = 1
	var started: Variant = module.begin_collection("player.1", source.position + Vector2(40, 0), source.position, 10, 1)
	_expect(started.is_ok, "depletion fixture should start collecting")
	module.advance_ticks(60)
	var ready: Array = module.drain_ready_cycles()
	var committed: Variant = module.commit_cycle(String(ready[0]["token"]))
	_expect(committed.is_ok and bool(committed.value["depleted"]), "last unit should remove the depleted source")
	_expect(module.sources.size() == 19, "depleted source should leave a population vacancy")
	module.advance_ticks(5939)
	_expect(module.sources.size() == 19, "vacancy should remain before the five-minute boundary")
	module.advance_ticks(1)
	_expect(module.sources.size() == 20, "five-minute replenishment should restore the map to twenty sources")
	var replacement = module.sources.values().back()
	_expect(replacement.capacity == 50 and replacement.remaining == 50, "replacement source should be born full")


## 执行 `module` 对应的模块操作。
## [param catalog] 调用方传入的 `catalog` 参数。
## [param requested_map_id] 调用方传入的 `requested_map_id` 参数。
## [param instance_id] 调用方传入的 `instance_id` 参数。
func _module(catalog, requested_map_id: String, instance_id: String):
	var navigation := FakeNavigation.new()
	for index: int in range(400):
		var x := float(index % 20) * 120.0 + 120.0
		var y := float(index / 20) * 120.0 + 120.0
		navigation.graph.add_point(index, Vector2(x, y))
	var module = MiningModuleScript.new()
	var configured := module.configure(catalog, requested_map_id, instance_id, 20, navigation)
	_expect(configured.is_ok, "mining module should configure for %s" % requested_map_id)
	return module


## 记录一项测试断言及其失败信息。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
