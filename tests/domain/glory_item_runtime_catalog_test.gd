extends SceneTree

const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
const ItemTextureResolver := preload(
	"res://scripts/client/presentation/items/item_presentation_texture_resolver.gd"
)
const CHASSIS_ID := "glory_equipment_tank1_c2ba1ac5af"
const HAIR_ID := "glory_equipment_1_7b41203496"
const ENERGY_ORE_ID := "item:material:078bc4104cd1"

var failures := PackedStringArray()
var assertions := 0


## 执行本测试脚本的全部验证并汇总结果。
func _initialize() -> void:
	var catalog = ItemCatalogScript.new()
	var initialized: Variant = catalog.initialize()
	_expect(initialized.is_ok, "统一物品目录应加载")
	if not initialized.is_ok:
		_finish()
		return
	var generated_count := 0
	var all_created := true
	for definition_id: String in catalog.definition_ids():
		if not definition_id.begins_with("glory_") and not definition_id.begins_with("item:"):
			continue
		generated_count += 1
		var created: Variant = catalog.create(definition_id, {"instance_id": "test.%s" % definition_id})
		if not created.is_ok:
			all_created = false
			break
	_expect(generated_count == 1270, "应遍历 1012 件装备和 258 个材料")
	_expect(all_created, "全部荣耀物品都应能组装为领域对象")
	var chassis: Variant = catalog.create(CHASSIS_ID, {"instance_id": "test.chassis"})
	_expect(chassis.is_ok and chassis.value is VehicleChassis, "新兵战车源行应成为 VehicleChassis")
	_expect(chassis.value.equipment_location == 0, "源 m_nLocation 应保留底盘 Location 0")
	var hair: Variant = catalog.create(HAIR_ID, {"instance_id": "test.hair"})
	_expect(hair.is_ok and hair.value is Clothing, "人物头发应成为 Clothing")
	_expect(hair.value.character_slot == "head" and hair.value.required_sex == "male", "头发槽位和源性别应生效")
	var chassis_icon := ItemTextureResolver.resolve(chassis.value.presentation_for("inventory"))
	var chassis_dialog := ItemTextureResolver.resolve(chassis.value.presentation_for("dialog"))
	var hair_icon := ItemTextureResolver.resolve(hair.value.presentation_for("inventory"))
	_expect(chassis_icon.get("texture") is AtlasTexture, "战车背包图应从荣耀 ALE 包加载")
	_expect(chassis_dialog.get("texture") is AtlasTexture, "战车装备面板图应从独立 dialog ALE 加载")
	_expect(hair_icon.get("texture") is AtlasTexture, "服装背包图应从荣耀 ALE 包加载")
	_expect(Vector2(chassis_dialog.get("origin", Vector2.ZERO)).is_finite(), "ALE 对话框原点应可供面板叠图")
	var energy_ore: Variant = catalog.create(ENERGY_ORE_ID, {"instance_id": "test.energy_ore"})
	var energy_icon := ItemTextureResolver.resolve(energy_ore.value.presentation_for("inventory"))
	_expect(energy_ore.is_ok and energy_icon.get("texture") is AtlasTexture, "矿石物品应使用对应 ACT 调色板背包图")
	_finish()


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
		print("GLORY_ITEM_RUNTIME_CATALOG_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
