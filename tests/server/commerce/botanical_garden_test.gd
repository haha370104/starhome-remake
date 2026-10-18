extends SceneTree

var checks := 0
var failures: Array[String] = []


## 用隔离角色验证采摘事务、持久化时钟及现有素材解析。
func _initialize() -> void:
	call_deferred("_run")


## 检查重启、满包、跨图、距离、旧版本和五类原料的完整路径。
func _run() -> void:
	var fixture := PlayerPanelServiceFixture.new()
	_check(fixture.initialize().is_ok, "初始化夹具")
	var catalog := fixture._service.item_catalog()
	var service := AuthoritativeGardenService.new()
	_check(service.initialize(catalog).is_ok, "采摘服务")
	var rules := service.rules
	var plant: BotanicalGardenCatalog.Plant = rules.plants[0]
	var state := fixture._state.duplicate_record()
	var old := state.to_dictionary()
	old.erase("garden")
	_check(PlayerStateRecord.from_dictionary(old).is_ok, "兼容无采摘记录的旧存档")
	state.map_id = rules.map_id
	state.position = plant.position
	var command := {"type": "harvest_garden", "plant_id": plant.id, "inventory_revision": state.inventory_revision}
	var before := state.to_dictionary()
	var result := service.execute(state, command, 1000)
	_check(result.is_ok, "原料入包候选")
	if not result.is_ok:
		push_error(result.error_message)
		quit(1)
		return
	var candidate: PlayerStateRecord = result.value.candidate
	_check(state.to_dictionary() == before, "候选与原状态隔离")
	_check(candidate.garden.remaining(plant.id, 1001) == 29, "成功才记录30秒再生")
	_check(candidate.inventory_stacks.size() == state.inventory_stacks.size() + 1, "产出一件原料")
	_check(not service.execute(candidate, command, 1031).is_ok, "过期后重放旧版本仍拒绝")
	command.inventory_revision = candidate.inventory_revision
	var restored := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(candidate.to_dictionary())))
	var restarted := AuthoritativeGardenService.new()
	restarted.initialize(catalog)
	_check(not restarted.execute(restored.value, command, 1001).is_ok, "重启不能提前采摘")
	_check(restarted.execute(restored.value, command, 1030).is_ok, "到期正常再生")
	_check(restarted.build_bundle(restored.value, {}, 1002).garden.plants[0].remaining_seconds == 28, "查询不重置时钟")
	state.position += Vector2(rules.interaction_radius + 1, 0)
	command.inventory_revision = state.inventory_revision
	_check(not service.execute(state, command, 1000).is_ok, "距离由权威位置决定")
	state.position = plant.position
	state.map_id = "other"
	_check(not service.execute(state, command, 1000).is_ok, "禁止跨地图采摘")
	state.map_id = rules.map_id
	state.inventory_capacity = state.inventory_stacks.size()
	before = state.to_dictionary()
	_check(not service.execute(state, command, 1000).is_ok and state.to_dictionary() == before, "满包不入账不扣冷却")
	_check(not GardenProgress.restore({plant.id: 12.5}).is_ok and not GardenProgress.restore({plant.id: true}).is_ok, "非法时钟拒绝")
	var mapper := PlayerStateMapper.new(catalog)
	_check(mapper.to_record(mapper.to_domain(candidate).value).value.garden.to_dictionary() == candidate.garden.to_dictionary(), "普通人物事务保留采摘时钟")
	print("Botanical garden: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总真实业务结果，失败时保留清晰诊断。
## [param condition] 是否符合期望。[param message] 失败上下文。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
