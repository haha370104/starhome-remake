extends SceneTree

var catalog := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var mapper: PlayerStateMapper
var policy := SmartAssistantPolicy.new()
var panel: SmartAssistantPanel
var checks := 0
var failures: Array[String] = []


## 延迟验证真实目录、使用事务与设置面板。
func _initialize() -> void:
	call_deferred("_run")


## 用实际物品校验补给决策、食品冷却、增益续用及高级导弹。
func _run() -> void:
	root.size = Vector2i(1100, 760)
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok, "初始化")
	mapper = PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new()
	var pack := _item("低级能量包", 10)
	var pizza := _item("比萨", 3)
	player.inventory.add_reward(pack)
	player.inventory.add_reward(pizza)
	panel = SmartAssistantPanel.new()
	root.add_child(panel)
	panel.position = Vector2(30, 30)
	panel.settings_changed.connect(policy.apply)
	panel.apply_supplies(player.inventory)
	_check(panel.energy_choice.item_count == 2 and panel.food_choice.item_count == 2, "清单只列实际能量包和食品")
	panel.toggles.enabled.button_pressed = true
	panel.toggles.auto_energy.button_pressed = true
	panel.energy_choice.select(1)
	panel.energy_choice.item_selected.emit(1)
	panel.energy_threshold.value = 50
	_check(policy.energy_definition_id == pack.definition_id and policy.energy_threshold == 0.5, "选择与阈值真实改变策略")
	player.vehicle.reserve_energy = 3500
	var now := int(Time.get_unix_time_from_system())
	_check(policy.next_supply(player, _vehicle(player), now) == pack.instance_id, "低能量选择指定堆叠")
	player = _use(player, policy.next_supply(player, _vehicle(player), now))
	_check(player.vehicle.reserve_energy == 9500 and player.inventory.find(pack.instance_id).quantity == 4, "真实手动使用事务批用六包")
	_check(policy.next_supply(player, _vehicle(player), now).is_empty(), "超过阈值不再补满尾包")
	player.vehicle.reserve_energy = 10000
	_check(policy.next_supply(player, _vehicle(player), now).is_empty(), "已满不请求")
	player.vehicle.reserve_energy = 100
	var medium := _item("中级能量包", 2)
	player.inventory.add_reward(medium)
	policy.energy_definition_id = medium.definition_id
	player = _use(player, policy.next_supply(player, _vehicle(player), now))
	_check(player.inventory.find(medium.instance_id).quantity == 1 and player.vehicle.reserve_energy == 10000, "余量不足一包仍复用单包规则")
	policy.energy_definition_id = pack.definition_id
	player.vehicle.reserve_energy = 0
	player.inventory.find(pack.instance_id).locked = true
	_check(policy.next_supply(player, _vehicle(player), now).is_empty(), "锁定包不请求")
	player.inventory.find(pack.instance_id).locked = false
	panel.toggles.auto_energy.button_pressed = false
	panel.toggles.auto_food.button_pressed = true
	panel.food_choice.select(1)
	panel.food_choice.item_selected.emit(1)
	_check(policy.food_definition_id == pizza.definition_id, "选择食品类型")
	_check(policy.next_supply(player, _vehicle(player), now) == pizza.instance_id, "没有所选增益时补食品")
	player = _use(player, pizza.instance_id)
	_check(player.food_status.bonus(13, now) == 10 and player.inventory.find(pizza.instance_id).quantity == 2, "原食品增益实际生效")
	_check(policy.next_supply(player, _vehicle(player), now + 2).is_empty(), "效果有效时不循环消耗")
	player.food_status.physical = 20
	_check(policy.next_supply(player, _vehicle(player), now).is_empty(), "体力低也遵守同类冷却")
	_check(policy.next_supply(player, _vehicle(player), now + 10) == pizza.instance_id, "冷却结束后补体力")
	player.food_status.physical = 100
	for effect: FoodEffect in player.food_status.active: effect.expires_at = now - 1
	_check(policy.next_supply(player, _vehicle(player), now + 10) == pizza.instance_id, "到期后续用所选食品")
	player.inventory.find(pizza.instance_id).locked = true
	_check(policy.next_supply(player, _vehicle(player), now + 10).is_empty(), "锁定食品不请求")
	player.inventory = Inventory.new()
	panel.apply_supplies(player.inventory)
	_check(panel.food_choice.item_count == 2 and String(panel.food_choice.get_item_metadata(1)) == pizza.definition_id, "耗尽后保留选定类型不代选")
	_check(policy.next_supply(player, _vehicle(player), now + 10).is_empty(), "耗尽后不使用其他食品")
	var saved := policy.snapshot()
	var restored := SmartAssistantPolicy.new()
	restored.apply(saved)
	_check(restored.snapshot() == saved, "新增偏好往返")
	restored.apply({"repair_threshold": NAN, "energy_threshold": INF, "physical_threshold": "bad"})
	_check(restored.repair_threshold == 0.5 and restored.energy_threshold == 0.3 and restored.physical_threshold == 0.5, "非法阈值默认值")
	_test_missiles()
	panel.apply_settings(saved)
	panel.apply_supplies(mapper.to_domain(fixture._state).value.inventory)
	panel.show_status("运行中 · 补给复用实际物品使用规则")
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/assistant_supplies.png")
	panel.free()
	for failure in failures: push_error(failure)
	print("Assistant supplies: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)


## 逐一检查目录实际武器，炮导模式接受所有导弹而拒绝火箭。
func _test_missiles() -> void:
	policy.apply({"enabled": true, "gun_missile_mode": true})
	var count := 0
	for id in catalog.definition_ids():
		var definition := catalog.definition(id)
		if String(definition.get("kind", "")) not in ["vehicle_weapon", "missile_weapon", "rocket_weapon"]: continue
		var created := catalog.create(id, {"instance_id": "tactical.test"})
		if not created.is_ok or not created.value is VehicleWeapon: continue
		var weapon: VehicleWeapon = created.value
		if weapon.combat_mode() not in ["missile", "rocket_launcher"]: continue
		var loadout := VehicleLoadout.new()
		loadout.restore(catalog.create("recruit_energy_cannon", {"instance_id": "primary.test"}).value)
		loadout.restore(weapon)
		_check((policy.next_attack_weapon("energy_cannon", loadout) == "missile") == (weapon.combat_mode() == "missile"), "实际副武器类型：" + weapon.display_name)
		if weapon.combat_mode() == "missile": count += 1
	_check(count > 1, "覆盖高级导弹而非只测新兵导弹")


## 用权威面板服务执行与右键完全相同的使用意图。
## [param player] 测试玩家。[param id] 策略选中的实例。
## 返回事务成功后的实际玩家。
func _use(player: Player, id: String) -> Player:
	var state: PlayerStateRecord = mapper.to_record(player).value
	var used := fixture._service.execute(state, {"type": "use_inventory_item", "instance_id": id, "inventory_revision": state.inventory_revision})
	_check(used.is_ok, "真实使用事务")
	return mapper.to_domain(used.value.candidate).value if used.is_ok else player


## 读取当前实际资源，模拟客户端接收的战斗资源投影。
## [param player] 当前玩家。
## 返回补给判断使用的最小快照。
func _vehicle(player: Player) -> Dictionary:
	return {"health": player.vehicle.health, "max_health": player.vehicle.max_health,
		"reserve_energy": player.vehicle.reserve_energy, "reserve_energy_capacity": player.vehicle.reserve_energy_capacity}


## 按原名称查找真实食品配置，不在测试重写效果。
## [param title] 原名称。[param amount] 测试数量。
## 返回目录创建的实例。
func _item(title: String, amount: int) -> ConsumableItem:
	for id in catalog.definition_ids():
		if catalog.display_name(id) == title: return catalog.create(id, {"instance_id": title, "quantity": amount}).value
	return null


## 汇总补给与显示行为断言。
## [param condition] 实际结果。[param label] 失败说明。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
