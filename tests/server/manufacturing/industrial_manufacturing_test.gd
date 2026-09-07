extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
const Service := preload("res://scripts/server/manufacturing/authoritative_manufacturing_service.gd")
const Stack := preload("res://scripts/server/persistence/inventory_stack_record.gd")
var failures := PackedStringArray()
var assertions := 0


## 验证工业配方身份、提炼／制造结算、重放保护与跨地图拒绝。
func _initialize() -> void:
	var fixture := Fixture.new()
	var service := Service.new()
	_expect(fixture.initialize().is_ok and service.initialize().is_ok, "工业依赖应初始化")
	if not failures.is_empty():
		_finish()
		return
	var state: PlayerStateRecord = fixture._state
	state.inventory_stacks.clear()
	state.map_id = "glory_nft_bl_factory1"
	state.character_skills["refining"] = {"level": 10, "current_exp": 0, "fractional_exp": 0.0}
	var iron := _find(service, state, "refining", "铁")
	_expect(not iron.is_empty(), "铁矿提炼应已恢复")
	if iron.is_empty():
		_finish()
		return
	_expect(int(iron.materials[0].required) == 10, "原版十个铁矿产一个铁")
	_supply(state, iron)
	var original := state.to_dictionary()
	var result := service.execute(state, _command(state, iron))
	_expect(result.is_ok and result.value.operation.succeeded, "提炼应成功")
	_expect(state.to_dictionary() == original, "服务不直接修改提交前存档")
	if result.is_ok:
		var candidate: PlayerStateRecord = result.value.candidate
		_expect(_quantity(candidate, String(iron.product_definition_id)) == 1, "提炼产物入包")
		_expect(_quantity(candidate, String(iron.materials[0].definition_id)) == 0, "提炼材料扣完")
		_expect(int(candidate.character_skills.refining.level) == 11, "提炼20点经验达到十级门槛，应升至十一级")
		_expect(not service.execute(candidate, _command(state, iron)).is_ok, "旧背包版本不得重复生产")
	for map_id: String in ["dragon_city_refinery_floor_2", "dragon_city_refinery_floor_3"]:
		state.map_id = map_id
		_expect(not _find(service, state, "refining", "铁").is_empty(), "提炼厂多层均可使用")
	state.map_id = "glory_nft_bl_armshop1"
	state.character_skills["manufacturing"] = {"level": 0, "current_exp": 0, "fractional_exp": 0.0}
	var beginner := _find(service, state, "alloy", "铜铁合金")
	_expect(not beginner.is_empty() and int(beginner.required_skill_level) == 0, "零级制造技能必须有入门配方")
	if not beginner.is_empty():
		_supply(state, beginner)
		var novice_result := service.execute(state, _command(state, beginner))
		_expect(novice_result.is_ok, "零级玩家可以生产第一件合金并学习：%s" % novice_result.error_message)
	state.character_skills["manufacturing"] = {"level": 320, "current_exp": 0, "fractional_exp": 0.0}
	var tank := _find(service, state, "equipment_manufacturing", "炎帝战车")
	_expect(not tank.is_empty(), "主装备制造必须包含炎帝")
	if tank.is_empty():
		_finish()
		return
	_expect(int(tank.required_skill_level) == 320 and tank.materials.size() == 4, "炎帝等级与四种材料来自原表")
	_expect(int(tank.materials[0].required) == 3 and int(tank.materials[1].required) == 100 \
		and int(tank.materials[2].required) == 999 and int(tank.materials[3].required) == 10, "炎帝材料数量无缺失")
	_supply(state, tank)
	var missing_materials := state.duplicate_record()
	missing_materials.inventory_stacks.clear()
	_expect(not service.execute(missing_materials, _command(missing_materials, tank)).is_ok, "缺少材料时拒绝且不凭空生成装备")
	var parsed_state := PlayerStateRecord.from_dictionary(state.to_dictionary())
	_expect(parsed_state.is_ok, "制造前存档合法：%s" % parsed_state.error_message)
	if not parsed_state.is_ok:
		_finish()
		return
	var insufficient: PlayerStateRecord = parsed_state.value
	insufficient.character_skills["manufacturing"] = {"level": 319, "current_exp": 0, "fractional_exp": 0.0}
	_expect(not service.execute(insufficient, _command(insufficient, tank)).is_ok, "未达等级不得生产炎帝")
	result = service.execute(state, _command(state, tank))
	_expect(result.is_ok, "无需征服者战车，直接制造炎帝")
	if result.is_ok:
		var candidate: PlayerStateRecord = result.value.candidate
		_expect(_quantity(candidate, String(tank.product_definition_id)) == 1, "炎帝产物进入背包")
		_expect(candidate.inventory_stacks[0].max_durability > 0 \
			and candidate.inventory_stacks[0].durability == candidate.inventory_stacks[0].max_durability, "制造产物应是具有完整耐久的装备对象")
		_expect(int(candidate.character_skills.manufacturing.current_exp) == 640, "制造发放640点经验")
		for ingredient: Dictionary in tank.materials:
			_expect(_quantity(candidate, String(ingredient.definition_id)) == 0, "制造材料原子扣除")
		var mapper := PlayerStateMapper.new(service._item_catalog)
		var mapped := mapper.to_domain(candidate)
		_expect(mapped.is_ok, "制造后的存档可反序列化为玩家聚合")
		if mapped.is_ok:
			var serialized := mapper.to_record(mapped.value)
			_expect(serialized.is_ok and _quantity(serialized.value, String(tank.product_definition_id)) == 1, "产物可完成存档往返")
	var restarted := Service.new()
	_expect(restarted.initialize().is_ok, "服务重建应成功")
	var again := restarted.execute(state, _command(state, tank))
	if result.is_ok and again.is_ok:
		_expect(result.value.candidate.inventory_stacks[0].stack_id != again.value.candidate.inventory_stacks[0].stack_id, "重启后生成的物品实例ID不能碰撞")
	var capped := state.duplicate_record()
	capped.character_skills["manufacturing"] = {"level": 700, "current_exp": 0, "fractional_exp": 0.0}
	_expect(service.execute(capped, _command(capped, tank)).is_ok, "满级仍可生产，只停止获得经验")
	var wrong_station := _command(state, tank)
	wrong_station.station_id = "alloy"
	_expect(not service.execute(state, wrong_station).is_ok, "合金机不得执行装备配方")
	state.map_id = "yian_harbor_hall_floor_1"
	_expect(not service.execute(state, _command(state, tank)).is_ok, "换图后旧窗口不能远程制造")
	_finish()


## 从权威设施投影查找指定产物。
## [param service] 已初始化服务。[param state] 权威记录。
## [param station] 设施类型。[param product] 产品显示名。
## 返回匹配的只读配方快照，缺失返回空字典。
func _find(service: RefCounted, state: PlayerStateRecord, station: String, product: String) -> Dictionary:
	var result: DomainResult = service.execute(state, {"type": "query_manufacturing", "station_id": station})
	if result.is_ok:
		for recipe: Dictionary in result.value.panel_bundle.manufacturing.recipes:
			if recipe.display_name == product:
				return recipe
	return {}


## 为测试记录填入真实最大堆叠范围内的配方材料。
## [param state] 测试存档。[param recipe] 权威配方快照。
func _supply(state: PlayerStateRecord, recipe: Dictionary) -> void:
	state.inventory_stacks.clear()
	for material: Dictionary in recipe.materials:
		var remaining := int(material.required)
		while remaining > 0:
			var quantity := mini(remaining, 99)
			var index := state.inventory_stacks.size()
			var stack := Stack.new()
			stack.stack_id = "industrial_test_%d" % index
			stack.item_definition_id = String(material.definition_id)
			stack.quantity = quantity
			stack.slot_index = index
			stack.container_id = "main"
			stack.position_px = Vector2i((index % 8) * 30, (index / 8) * 30)
			stack.footprint_px = Vector2i(30, 30)
			state.inventory_stacks.append(stack)
			remaining -= quantity


## 构造不携带数值和材料的生产意图。
## [param state] 提供背包版本。[param recipe] 选定配方。
## 返回网络兼容命令。
func _command(state: PlayerStateRecord, recipe: Dictionary) -> Dictionary:
	return {"type": "craft_recipe", "station_id": recipe.station_id,
		"recipe_id": recipe.recipe_id, "inventory_revision": state.inventory_revision}


## 统计指定物品定义的背包数量。
## [param state] 玩家存档。[param definition_id] 物品稳定身份。
## 返回跨堆叠总数量。
func _quantity(state: PlayerStateRecord, definition_id: String) -> int:
	var total := 0
	for stack: InventoryStackRecord in state.inventory_stacks:
		if stack.item_definition_id == definition_id:
			total += stack.quantity
	return total


## 收集断言失败而不中断后续检查。
## [param condition] 验证条件。[param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 汇总测试结果，以非零退出码报告失败。
func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	print("INDUSTRIAL_MANUFACTURING: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
