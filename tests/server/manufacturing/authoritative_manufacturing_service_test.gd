extends SceneTree

const FixtureScript := preload("res://tests/fixtures/player_panel_service_fixture.gd")
const ServiceScript := preload(
	"res://scripts/server/manufacturing/authoritative_manufacturing_service.gd"
)
const StackRecordScript := preload("res://scripts/server/persistence/inventory_stack_record.gd")

var failures := PackedStringArray()
var assertions := 0


## 验证裁缝/烹饪配方查询、材料事务、产物入包和技能结算。
func _initialize() -> void:
	var fixture := FixtureScript.new()
	var fixture_result: DomainResult = fixture.initialize()
	var service := ServiceScript.new()
	var service_result: DomainResult = service.initialize()
	_expect(fixture_result.is_ok and service_result.is_ok, "权威制造服务应完成初始化")
	if not fixture_result.is_ok or not service_result.is_ok:
		_finish()
		return
	var state: PlayerStateRecord = fixture._state
	state.character_skills["tailoring"] = {
		"level": 110, "current_exp": 0, "fractional_exp": 0.0,
	}
	_append_stack(state, "material.synthetic_cotton", "item:material:b366aac2e554", 1, 2, [120, 0])
	_append_stack(state, "material.synthetic_thread", "item:material:0f2b9045caf2", 1, 3, [150, 0])
	_append_stack(state, "material.iron", "item:material:8f615d2ef879", 5, 4, [180, 0])
	var queried: DomainResult = service.execute(state, {
		"type": "query_manufacturing", "station_id": "tailoring",
	})
	_expect(queried.is_ok, "裁缝机查询应返回权威配方")
	if queried.is_ok:
		var recipes: Array = queried.value.panel_bundle.manufacturing.recipes
		_expect(recipes.size() == 65, "裁缝机应登记荣耀 sewlist 的65条可执行配方")
		_expect(_find_recipe(recipes, "裁缝紧身裤(男)").can_craft, "材料与等级满足时配方应可制作")
	var crafted: DomainResult = service.execute(state, {
		"type": "craft_recipe",
		"station_id": "tailoring",
		"recipe_id": "glory_recipe_manufacturing_076",
		"inventory_revision": state.inventory_revision,
	})
	_expect(crafted.is_ok and bool(crafted.value.operation.succeeded), "裁缝紧身裤应由权威事务制作成功")
	if crafted.is_ok:
		var candidate: PlayerStateRecord = crafted.value.candidate
		_expect(_stack_quantity(candidate, "item:material:8f615d2ef879") == 0, "制作应原子消耗5个铁")
		_expect(_stack_quantity(candidate, "glory_equipment_1_09f6c8233d") == 1, "产物应作为同一物品对象进入背包")
		_expect(int(candidate.character_skills.tailoring.current_exp) == 33, "成功裁缝应发放配方记录的33点经验")
	var cooking: DomainResult = service.execute(state, {
		"type": "query_manufacturing", "station_id": "cooking",
	})
	_expect(cooking.is_ok and not cooking.value.panel_bundle.manufacturing.recipes.is_empty(), "烹饪台应只下发名称和产物均可解析的旧客户端配方")
	_finish()


## 向测试存档加入一个有效背包堆叠。
## [param state] 待修改的测试存档。
## [param stack_id] 物品实例 ID。
## [param definition_id] 稳定物品定义 ID。
## [param quantity] 数量。
## [param slot_index] 背包顺序。
## [param position] 二维像素位置。
func _append_stack(
	state: PlayerStateRecord,
	stack_id: String,
	definition_id: String,
	quantity: int,
	slot_index: int,
	position: Array,
) -> void:
	var parsed: DomainResult = StackRecordScript.from_dictionary({
		"stack_id": stack_id,
		"item_definition_id": definition_id,
		"quantity": quantity,
		"slot_index": slot_index,
		"container_id": "main",
		"position_px": position,
		"footprint_px": [30, 30],
		"locked": false,
		"bound": false,
		"max_durability": 0,
		"durability": 0,
	})
	if parsed.is_ok:
		state.inventory_stacks.append(parsed.value)


## 按显示名查询配方测试快照。
## [param recipes] 配方视图数组。
## [param display_name] 目标名称。
## 返回匹配字典；不存在时为空。
func _find_recipe(recipes: Array, display_name: String) -> Dictionary:
	for recipe: Dictionary in recipes:
		if String(recipe.get("display_name", "")) == display_name:
			return recipe
	return {}


## 统计存档中指定定义的物品数量。
## [param state] 制作后的存档。
## [param definition_id] 稳定物品定义 ID。
## 返回跨堆叠数量。
func _stack_quantity(state: PlayerStateRecord, definition_id: String) -> int:
	var total := 0
	for stack: InventoryStackRecord in state.inventory_stacks:
		if stack.item_definition_id == definition_id:
			total += stack.quantity
	return total


## 记录一条测试断言。
## [param condition] 条件是否成立。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出测试结果并结束进程。
func _finish() -> void:
	if failures.is_empty():
		print("AUTHORITATIVE_MANUFACTURING_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
