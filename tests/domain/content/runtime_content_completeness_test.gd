extends SceneTree

const CatalogScript := preload(
	"res://scripts/domain/content/runtime_content_completeness_catalog.gd"
)

var failures := PackedStringArray()
var assertions := 0


func _initialize() -> void:
	var loaded: Variant = CatalogScript.load_default()
	_expect(loaded.is_ok, "运行内容覆盖清单应加载")
	if not loaded.is_ok:
		_finish()
		return
	var catalog = loaded.value
	_expect(catalog.catalog_summary("maps").get("runtime_ready") == 810, "应挂载 810 个地图来源")
	_expect(catalog.catalog_summary("animations").get("runtime_total") == 13994, "应索引基础及调色板动画")
	_expect(catalog.catalog_summary("monsters").get("runtime_definitions") == 119, "应激活 119 个怪物定义")
	_expect(catalog.catalog_summary("items").get("total_runtime_definitions") == 1284, "应激活 1284 个物品定义")
	_expect(catalog.catalog_summary("recipes").get("registered_records") == 346, "应注册 346 条配方")
	_expect(catalog.catalog_summary("minerals").get("runtime_definitions") == 35, "应激活 35 类矿源")
	_expect(catalog.exception("map_package_missing").get("count") == 4, "四个缺包地图必须显式保留")
	_expect(catalog.exception("item_asset_missing_from_glory_package").get("count") == 463, "缺失素材引用必须显式保留")
	_expect(catalog.exceptions().size() == 4, "所有不可恢复边界应集中列示")
	_finish()


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("RUNTIME_CONTENT_COMPLETENESS_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
