extends SceneTree

var _checks := 0
var _failures := 0


## 验证先保管加工再移动锻造，来源上限元数据不变成免费的目标锻造。
func _initialize() -> void:
	var catalog := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok, "init")
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new(40, 0, 1000000)
	for row: Dictionary in [
		{"id": "recruit_tank", "state": {"instance_id": "source", "forging": {"extensions": {"1": 50}}, "processing": {"increments": {"max_health": 75}}}},
		{"id": "recruit_tank", "state": {"instance_id": "target"}},
		{"id": "equipment_memory_processing", "state": {"instance_id": "ordinary"}},
		{"id": "equipment_memory_forging", "state": {"instance_id": "forging"}},
		{"id": "equipment_memory_stabilizer", "state": {"instance_id": "stabilizer", "quantity": 10}},
	]: _check(player.inventory.add_reward(catalog.create(row.id, row.state).value).is_ok, "stock")
	var before: Dictionary = mapper.to_record(player).value.to_dictionary()
	var invalid := _act(player, catalog, "source", "forging", "extract")
	_check(not invalid.is_ok and invalid.error_message.contains("先提取普通加工"), "cannot remove supporting cap")
	_check(mapper.to_record(player).value.to_dictionary() == before, "no mutation on invalid order")
	_check(_act(player, catalog, "source", "ordinary", "extract").is_ok, "extract expanded processing")
	var module := player.inventory.find("ordinary") as EquipmentMemoryModule
	_check(module.memory.source_forging.extensions.get(1) == 50 and not module.memory.equipment_state().has("forging"), "metadata never applied")
	var record: PlayerStateRecord = mapper.to_record(player).value
	var parsed := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(record.to_dictionary())))
	if not parsed.is_ok: push_error(parsed.error_message); quit(1); return
	var mapped := mapper.to_domain(parsed.value)
	if not mapped.is_ok: push_error(mapped.error_message); quit(1); return
	player = mapped.value
	_check(player.inventory.find("ordinary").memory.processing.bonus("max_health") == 75, "above base payload survives save")
	_check(not _act(player, catalog, "target", "ordinary", "transfer").is_ok, "unforged target cannot accept elevated processing")
	_check(player.inventory.find("target").forging.extensions.is_empty(), "no free extension")
	_check(_act(player, catalog, "source", "forging", "extract").is_ok, "extract extension after processing")
	_check(player.inventory.find("source").forging.extensions.is_empty(), "extension moved not copied")
	_check(_act(player, catalog, "target", "forging", "transfer").is_ok, "install actual cap")
	_check(_act(player, catalog, "target", "ordinary", "transfer").is_ok, "restore full processing")
	_check(player.inventory.find("target").base_max_health == 145 and player.inventory.find("ordinary") == null and player.inventory.find("forging") == null, "full chain exact stats consumes modules")
	var forged := catalog.create("equipment_memory_processing", {"equipment_memory": {"version": 1, "source_definition_id": "recruit_tank", "module_type": 1, "payload": {"increments": {"max_health": 75}}, "source_forging": {"extensions": {"1": 501}}}})
	_check(not forged.is_ok, "metadata obeys original cap")
	_test_ammunition(player, catalog)
	print("Equipment memory forging: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 弹仓加工提取有可见的裁弹预览；失败保留弹药，成功仅裁去超出部分。
## [param player] 隔离测试玩家。
## [param catalog] 实际目录。
func _test_ammunition(player: Player, catalog: ItemCatalog) -> void:
	player.inventory.add_reward(catalog.create("starter_missile", {"instance_id": "missile", "processing": {"increments": {"ammunition_capacity": 50}}, "magazine": {"remaining": 140}}).value)
	player.inventory.add_reward(catalog.create("equipment_memory_processing", {"instance_id": "ammo.module"}).value)
	var service := EquipmentMemoryService.new(catalog)
	var snapshot := service.snapshot(player, {"instance_id": "missile", "material_id": "ammo.module", "mode": "extract", "use_stabilizer": true})
	_check(snapshot.preview.can_execute and snapshot.preview.text.contains("40发"), "visible ammo loss")
	_check(_act(player, catalog, "missile", "ammo.module", "extract").is_ok, "extract capacity")
	_check(player.inventory.find("missile").magazine.remaining == 100, "discard excess only")
	_check(_act(player, catalog, "missile", "ammo.module", "transfer").is_ok, "restore capacity")
	_check(player.inventory.find("missile").ammunition_capacity() == 150 and player.inventory.find("missile").magazine.remaining == 100, "no free ammo on restoration")


## 用稳压剂调用正式事务，随机样本固定为成功。
## [param player] 测试玩家。
## [param catalog] 权威目录。
## [param id] 装备实例。
## [param module] 模块身份。
## [param mode] 提取或转移。
## 返回领域结算结果。
func _act(player: Player, catalog: ItemCatalog, id: String, module: String, mode: String) -> DomainResult:
	return PlayerEquipmentMemoryActions.execute(player, catalog, id, module, mode, true, player.inventory.revision, true, 0)


## 累计行为断言。
## [param condition] 当前结果。
## [param label] 失败原因。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
