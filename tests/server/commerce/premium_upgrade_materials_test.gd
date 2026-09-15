extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
var failures: Array[String] = []
var checks := 0
var service := AuthoritativeCommerceService.new()
var items := ItemCatalog.new()
var fixture := Fixture.new()


## 内容挂载后验证真实商城购买、各阶段预算及材料的稳定身份。
func _initialize() -> void:
	call_deferred("_run")


## 逐阶段购买所需全部收费材料，验证权威金额、边界、原子性和存档重放。
func _run() -> void:
	_expect(items.initialize().is_ok and fixture.initialize().is_ok and service.initialize().is_ok, "权威物品、商城与夹具初始化")
	var state := fixture._state.duplicate_record()
	var query := service.execute(state, {"type": "query_premium_shop"})
	_expect(query.is_ok, "商城查询成功")
	if not query.is_ok:
		_finish()
		return
	var offers: Array = query.value.panel_bundle.premium_shop.offers
	var material_offers: Array = offers.filter(func(row: Dictionary) -> bool: return row.family == "upgrade_material")
	_expect(material_offers.size() == 7, "七种缺失升级材料均上架")
	_expect(items.display_name("item:material:f65184d5f9b2") == "冲击晶体", "冲击晶体复用旧占位ID而非另建同类物品")
	for offer: Dictionary in material_offers:
		var priced_state := fixture._state.duplicate_record()
		priced_state.amethyst = int(offer.price) * 3
		var before := priced_state.to_dictionary()
		var command := {"type": "buy_premium_item", "definition_id": offer.definition_id, "quantity": 3,
			"inventory_revision": priced_state.inventory_revision, "price": 1, "amethyst": 9999999}
		var bought := service.execute(priced_state, command)
		_expect(bought.is_ok and priced_state.to_dictionary() == before, "材料批量购买不修改已提交状态")
		if bought.is_ok:
			var next: PlayerStateRecord = bought.value.candidate
			_expect(next.amethyst == 0 and _quantity(next, offer.definition_id) == 3, "按真实单价扣三件并入包")
			var restored := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(next.to_dictionary())))
			_expect(restored.is_ok and _quantity(restored.value, offer.definition_id) == 3 and not service.execute(restored.value, command).is_ok,
				"JSON重启后保留材料且旧版本不能重复扣款")
		priced_state.amethyst -= 1
		before = priced_state.to_dictionary()
		_expect(not service.execute(priced_state, command).is_ok and priced_state.to_dictionary() == before, "少一枚紫晶时整体拒绝")
		priced_state.amethyst = 100000
		priced_state.inventory_capacity = priced_state.inventory_stacks.size()
		_expect(not service.execute(priced_state, command).is_ok and priced_state.amethyst == 100000, "背包满不扣款")
		priced_state.inventory_capacity = 40
		for invalid: Variant in [0, -1, 1.5, "2", true, INF, 100]:
			command.quantity = invalid
			_expect(service.execute(priced_state, command).error_code == &"commerce.invalid_quantity", "非法数量在服务端拒绝")
		var definition := items.definition(offer.definition_id)
		if offer.display_name != "加工石":
			_expect(not ItemPresentationTextureResolver.resolve(definition.presentation).is_empty(), "六种材料加载各自荣耀原图")
		else:
			_expect(definition.source_audit.asset_status == "local_missing_and_official_exact_path_404", "加工石明确记录原图缺失")
	var stages := 0
	for offer: Dictionary in offers:
		if offer.family == "upgrade_material":
			continue
		var source_class := String(items.definition(offer.definition_id).source_class)
		var coefficient := 1800 if source_class in ["NewGunJoint", "HuoLiJieHeQi"] else (1200 if source_class == "NewFireGunJoint" else 1500)
		_expect(offer.upgrade_plans.size() == (5 if offer.family == "new_joint" else 4), "每件商品覆盖全部支持阶段")
		for plan: Dictionary in offer.upgrade_plans:
			stages += 1
			var tier := maxi(int(plan.current_level), 1)
			_expect(int(plan.premium_cost) == tier * coefficient and plan.premium_cost >= tier * 1000 and plan.premium_cost <= tier * 2000,
				"强化当前等级计费，能量炮/火力高、火箭低且所有阶段在预算内")
			var buyer := fixture._state.duplicate_record()
			buyer.amethyst = int(plan.premium_cost)
			for requirement: Dictionary in plan.premium_materials:
				var bought := service.execute(buyer, {"type": "buy_premium_item", "definition_id": requirement.definition_id,
					"quantity": requirement.quantity, "inventory_revision": buyer.inventory_revision})
				_expect(bought.is_ok, "用阶段预算逐项购买所有材料")
				if bought.is_ok:
					buyer = bought.value.candidate
					_expect(_quantity(buyer, requirement.definition_id) == int(requirement.quantity), "购买数量与阶段需求一致")
			_expect(buyer.amethyst == 0 and buyer.currency == fixture._state.currency, "实际购物合计等于阶段预算，不消耗金币")
	_expect(stages == 40, "九类接合器四十个阶段全部验证")
	_finish()


## 统计存档内实际材料数量。
## [param state] 购买后的候选存档。
## [param id] 商品定义ID。
## 返回跨堆叠总量。
func _quantity(state: PlayerStateRecord, id: String) -> int:
	var count := 0
	for stack: InventoryStackRecord in state.inventory_stacks:
		if stack.item_definition_id == id:
			count += stack.quantity
	return count


## 累计权威行为断言。
## [param condition] 要求成立的业务条件。
## [param message] 失败原因。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


## 输出本轮检查结果并退出。
func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	print("PREMIUM_UPGRADE_MATERIALS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
