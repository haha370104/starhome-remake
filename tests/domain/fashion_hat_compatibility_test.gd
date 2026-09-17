extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证五顶季节帽的新部位及已穿上衣槽的旧档无损兼容。
func _initialize() -> void:
	var items := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	_check(items.initialize().is_ok and fixture.initialize().is_ok, "初始化")
	var mapper := PlayerStateMapper.new(items)
	var hats := 0
	for id: String in items.clothing_improvement_rules.slots:
		if not items.definition(id).has("legacy_character_slot"): continue
		hats += 1
		var fresh: Clothing = items.create(id, {"instance_id": "fresh"}).value
		_check(fresh.character_slot == "head", "新帽正确归头部")
		var old: Clothing = items.create(id, {"instance_id": "legacy", "equipped_character_slot": "upper_body", "clothing_improvement": {"level": 3, "attribute": "defense"}}).value
		var player: Player = mapper.to_domain(fixture._state).value
		_check(player.character_equipment.restore(old).is_ok and player.character_equipment.restore(fresh).is_ok, "旧上衣帽和头饰共存")
		var recorded := mapper.to_record(player)
		var restored := mapper.to_domain(recorded.value)
		_check(restored.is_ok, "旧装备槽可重启")
		player = restored.value
		_check(player.character_equipment.at("upper_body").instance_id == "legacy" and player.character_equipment.at("head").instance_id == "fresh", "不挤掉任何实例")
		var current := CurrentPlayer.new(items)
		_check(current.apply_bundle(fixture._service.build_bundle(recorded.value)), "客户端兼容槽位")
		_check(current.character_equipment.at("upper_body").improvement.level == 3, "兼容保留改良")
		_check(player.unequip_character_item("upper_body", player.inventory.revision, player.revision).is_ok, "旧帽卸下")
		_check(player.inventory.find("legacy").character_slot == "head", "卸下后使用正确部位")
		player.sex = fresh.required_sex
		_check(player.equip_character_item("legacy", "head", player.inventory.revision, player.revision).is_ok, "再次穿戴进头部")
		_check(player.inventory.find("fresh") != null, "替换头饰安全回包")
		var fake: Clothing = items.create("male_sleeveless_shirt", {"instance_id": "fake", "equipped_character_slot": "head"}).value
		_check(fake.character_slot == "upper_body", "兼容不能篡改其他服装槽位")
	_check(hats == 5, "修正范围五顶帽子")
	print("Fashion hat compatibility: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计槽位兼容行为断言。
## [param condition] 期望条件。
## [param label] 失败说明。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
