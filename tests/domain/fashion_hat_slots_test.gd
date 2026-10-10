extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证五顶季节帽只使用当前定义的头部槽位。
func _initialize() -> void:
	var items := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	_check(items.initialize().is_ok and fixture.initialize().is_ok, "初始化")
	var mapper := PlayerStateMapper.new(items)
	var hats := 0
	for id: String in items.clothing_improvement_rules.slots:
		if items.clothing_improvement_rules.slots[id] != "head": continue
		hats += 1
		var fresh: Clothing = items.create(id, {"instance_id": "fresh"}).value
		_check(fresh.character_slot == "head" and not items.definition(id).has("legacy_character_slot"), "帽子定义直接使用头部槽位")
		var player: Player = mapper.to_domain(fixture._state).value
		_check(player.character_equipment.restore(fresh).is_ok, "头饰可装入头部槽位")
		var recorded := mapper.to_record(player)
		var restored := mapper.to_domain(recorded.value)
		_check(restored.is_ok and restored.value.character_equipment.at("head").definition_id == id, "头部槽位往返保持")
	_check(hats == 5, "修正范围五顶帽子")
	print("Fashion hat slots: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计槽位行为断言。
## [param condition] 期望条件。
## [param label] 失败说明。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
