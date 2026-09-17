extends SceneTree

var _items := ItemCatalog.new()
var _fixture := PlayerPanelServiceFixture.new()
var _service := AuthoritativeCommerceService.new()
var _mapper: PlayerStateMapper
var _checks := 0
var _failures := 0
var _fashion := ""
const FIBER := "clothing_fiber_defense"


## 覆盖权威改良、跨堆叠消耗、绑定传播、购买定价及重复请求。
func _initialize() -> void:
	_check(_items.initialize().is_ok and _fixture.initialize().is_ok and _service.initialize().is_ok, "初始化")
	_mapper = PlayerStateMapper.new(_items)
	for id: String in _items.clothing_improvement_rules.slots:
		if _items.definition(id).required_sex == "male" and _items.clothing_improvement_rules.slots[id] == "upper_body":
			_fashion = id
			break
	var player := _player()
	var state: PlayerStateRecord = _mapper.to_record(player).value
	var before := state.to_dictionary()
	var command := {"type": "improve_clothing", "instance_id": "fashion", "material_id": "fiber", "material_quantity": 2, "inventory_revision": player.inventory.revision, "chance": 0, "level": 100}
	var result := _service.execute(state, command)
	_check(result.is_ok and state.to_dictionary() == before, "隔离事务")
	if not result.is_ok: push_error(result.error_message); quit(1); return
	player = _mapper.to_domain(result.value.candidate).value
	_check(player.inventory.find("fashion").improvement.level == 1 and player.inventory.find("fashion").bound, "权威等级和绑定")
	_check(player.inventory.find("fiber").quantity == 18 and player.inventory.currency == 1000000, "材料一次性扣除，无额外手续费")
	_check(not _service.execute(result.value.candidate, command).is_ok, "拒绝重复请求")
	var query := _service.execute(result.value.candidate, {"type": "query_clothing_improvement", "instance_id": "fashion", "material_id": "fiber", "material_quantity": 2})
	_check(query.is_ok and not query.value.changed and query.value.panel_bundle.clothing_improvement.preview.can_execute, "查询不写存档")
	_check(JSON.parse_string(JSON.stringify(query.value.panel_bundle)).clothing_improvement.preview.chance == 1, "安全序列化")
	var current := CurrentPlayer.new(_items)
	_check(current.apply_bundle(query.value.panel_bundle) and current.inventory.find("fashion").improvement.level == 1, "客户端快照")
	var bought := _service.execute(result.value.candidate, {"type": "buy_clothing_improvement_item", "definition_id": FIBER, "quantity": 9999, "inventory_revision": player.inventory.revision, "price": 1})
	_check(bought.is_ok and bought.value.candidate.currency == 800020, "大批量纤维和权威定价")
	var service := ClothingImprovementService.new(_items)
	var offers: Array = service.snapshot(player, {}).offers
	_check(offers.size() > 20, "同角色时装及七种纤维获取链")
	for offer: Dictionary in offers:
		var definition := _items.definition(offer.definition_id)
		_check(definition.get("required_sex", "any") in ["male", "any"], "不卖异性时装")
	var purchase := _service.execute(result.value.candidate, {"type": "buy_clothing_improvement_item", "definition_id": _fashion, "quantity": 1, "inventory_revision": player.inventory.revision})
	_check(purchase.is_ok and purchase.value.candidate.currency == 990000, "时装购买")
	for problem: String in ["locked", "fiber_locked", "broken", "installed", "wrong", "missing", "quantity", "stale", "roll", "maximum"]:
		player = _player()
		var item: Clothing = player.inventory.find("fashion")
		if problem == "locked": item.locked = true
		if problem == "fiber_locked": player.inventory.find("fiber").locked = true
		if problem == "broken": item.durability = 0
		if problem == "installed": player.equip_character_item("fashion", "upper_body", player.inventory.revision, player.revision)
		if problem == "wrong": item.improvement = ClothingImprovement.restore({"attribute": "max_health", "level": 1}).value
		if problem == "missing": player.inventory.find("fiber").quantity = 1
		if problem == "maximum": item.improvement = ClothingImprovement.restore({"attribute": "defense", "level": 100}).value
		before = _mapper.to_record(player).value.to_dictionary()
		var rejected := PlayerClothingImprovementActions.execute(player, "fashion", "fiber", 0 if problem == "quantity" else 2, player.inventory.revision - 1 if problem == "stale" else player.inventory.revision, NAN if problem == "roll" else 0)
		_check(not rejected.is_ok and _mapper.to_record(player).value.to_dictionary() == before, "原子拒绝 " + problem)
	player = _player()
	var failed := PlayerClothingImprovementActions.execute(player, "fashion", "fiber", 1, player.inventory.revision, 0.5)
	_check(failed.is_ok and not failed.value.success and player.inventory.find("fiber").quantity == 19, "失败仅消耗纤维")
	_check(player.inventory.find("fashion").improvement.attribute.is_empty() and player.inventory.find("fashion").improvement.level == 0, "首次失败不锁方向")
	player = _player()
	player.inventory.find("fashion").improvement = ClothingImprovement.restore({"attribute": "defense", "level": 99}).value
	player.inventory.find("fiber").quantity = 9999
	_check(player.inventory.add_reward(_items.create(FIBER, {"instance_id": "fiber2", "quantity": 9999, "bound": true}).value).is_ok, "第二堆材料")
	var final := PlayerClothingImprovementActions.execute(player, "fashion", "fiber", 10486, player.inventory.revision, 0)
	_check(final.is_ok and player.inventory.find("fashion").improvement.level == 100, "高级改良跨堆叠成功")
	_check(player.inventory.count_definition(FIBER) == 9512, "跨堆叠准确扣料")
	player = _player()
	while player.inventory.items().size() < player.inventory.capacity:
		player.inventory.add_reward(_items.create("beginner_engine", {"instance_id": "filler" + str(player.inventory.items().size())}).value)
	before = _mapper.to_record(player).value.to_dictionary()
	var full := service.execute(player, {"type": "buy_clothing_improvement_item", "definition_id": _fashion, "quantity": 1, "inventory_revision": player.inventory.revision})
	_check(not full.is_ok and _mapper.to_record(player).value.to_dictionary() == before, "背包满不扣钱")
	_check(PlayerClothingImprovementActions.execute(player, "fashion", "fiber", 2, player.inventory.revision, 0).is_ok, "背包满仍可原位改良")
	print("Clothing improvement authority: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 构造可穿原版时装和绑定纤维的独立玩家。
## 返回隔离测试聚合。
func _player() -> Player:
	var player: Player = _mapper.to_domain(_fixture._state).value
	player.inventory.currency = 1000000
	_check(player.inventory.add_reward(_items.create(_fashion, {"instance_id": "fashion"}).value).is_ok, "给予时装")
	_check(player.inventory.add_reward(_items.create(FIBER, {"instance_id": "fiber", "quantity": 20, "bound": true}).value).is_ok, "给予纤维")
	return player


## 记录事务行为断言。
## [param condition] 实际结果。
## [param label] 诊断说明。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
