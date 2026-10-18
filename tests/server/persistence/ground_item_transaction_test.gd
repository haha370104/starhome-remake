extends SceneTree

class FailingRepository extends FilePlayerStateRepository:
	var reject_write := false
	## 注入真实提交边界的写盘失败，验证玩家和地面同时回滚。
	## [param document] 待写入的完整文档。
	## 返回注入失败或真实原子文件结果。
	func _persist_document(document: Dictionary) -> DomainResult:
		return DomainResult.failure(&"persistence.storage_error", "injected failure") if reject_write else super(document)

var checks := 0
var failures: Array[String] = []


## 验证整件物品迁移、失败回滚、重启及旧档升级。
func _initialize() -> void:
	var fixture := PlayerPanelServiceFixture.new()
	_check(fixture.initialize().is_ok, "fixture")
	var catalog := fixture._service.item_catalog()
	var mapper := PlayerStateMapper.new(catalog)
	var state := fixture._state
	var path := "user://ground-transaction.json"
	var legacy := {"schema_version": 2, "players": {state.character_id: state.to_dictionary()}, "migration_history": [1, 2]}
	_check(AtomicJsonFile.write_document(ProjectSettings.globalize_path(path), legacy).is_ok, "old save fixture")
	var repository := FailingRepository.new(path)
	_check(repository.initialize().is_ok and repository.current_schema_version() == 3, "schema two upgrades without deleting player")
	var player: Player = mapper.to_domain(repository.load_player(state.character_id).value).value
	var engine := player.inventory.find("inventory.spare_engine") as VehicleEngine
	engine.processing.apply(catalog.processing_rules.profile(engine.definition_id), catalog.processing_rules.material("item:material:02212ea88168"))
	engine.refresh_processed_stats()
	engine.durability = 321
	engine.usage.progress["movement"] = 12.5
	var original: Dictionary = InventoryStackRecord.from_item(engine, 0).value.to_dictionary()
	_check(not GroundItem.drop_from(player, "inventory.training_shirt", player.inventory.revision, "map.a", Vector2.ZERO, Vector2.ZERO).is_ok, "bound item rejected")
	_check(not GroundItem.drop_from(player, engine.instance_id, player.inventory.revision - 1, "map.a", Vector2.ZERO, Vector2.ZERO).is_ok, "stale inventory rejected")
	_check(not GroundItem.drop_from(player, engine.instance_id, player.inventory.revision, "map.a", Vector2.ZERO, Vector2(126, 0)).is_ok, "far drop rejected")
	var dropped := GroundItem.drop_from(player, engine.instance_id, player.inventory.revision, "map.a", Vector2.ZERO, Vector2.ZERO)
	_check(dropped.is_ok and player.inventory.find(engine.instance_id) == null, "whole item removed from candidate")
	var record: GroundItemRecord = GroundItemRecord.from_domain(dropped.value).value
	var candidate: PlayerStateRecord = mapper.to_record(player).value
	repository.reject_write = true
	_check(not repository.save_ground_transfer(candidate, 0, record, "").is_ok, "drop write fails")
	_check(repository.ground_items().is_empty() and repository.load_player(state.character_id).value.inventory_stacks.size() == 2, "failed drop preserves both owners")
	repository.reject_write = false
	_check(repository.save_ground_transfer(candidate, 0, record, "").is_ok, "drop commits once")
	var restarted := FailingRepository.new(path)
	_check(restarted.initialize().is_ok and restarted.ground_items().size() == 1, "ground survives restart")
	var saved: PlayerStateRecord = restarted.load_player(state.character_id).value
	player = mapper.to_domain(saved).value
	var recovered: GroundItem = restarted.ground_items()[0].to_domain(catalog).value
	_check(not recovered.receive_into(player, "wrong.map", Vector2.ZERO).is_ok, "cross-map pickup rejected")
	_check(not recovered.receive_into(player, "map.a", Vector2(126, 0)).is_ok, "distant pickup rejected")
	player.inventory.capacity = 1
	_check(not recovered.receive_into(player, "map.a", Vector2.ZERO).is_ok, "full inventory preserves ground item")
	player.inventory.capacity = 40
	_check(recovered.receive_into(player, "map.a", Vector2.ZERO).is_ok, "pickup accepts intact item")
	candidate = mapper.to_record(player).value
	restarted.reject_write = true
	_check(not restarted.save_ground_transfer(candidate, saved.revision, null, record.loot_id).is_ok, "pickup write fails")
	_check(restarted.ground_items().size() == 1 and restarted.load_player(state.character_id).value.inventory_stacks.size() == 1, "failed pickup preserves both owners")
	restarted.reject_write = false
	_check(restarted.save_ground_transfer(candidate, saved.revision, null, record.loot_id).is_ok, "pickup commits once")
	_check(not restarted.save_ground_transfer(candidate, saved.revision + 1, null, record.loot_id).is_ok, "duplicate pickup rejected")
	player = mapper.to_domain(restarted.load_player(state.character_id).value).value
	var after: Dictionary = InventoryStackRecord.from_item(player.inventory.find(engine.instance_id), 0).value.to_dictionary()
	original.erase("position_px")
	after.erase("position_px")
	_check(original == after, "identity and every growth field survive drop, disk, restart and pickup")
	_check(restarted.ground_items().is_empty(), "ground ownership removed")
	print("GROUND_ITEM_TRANSACTION checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 收集事务边界断言。
## [param condition] 预期为真。[param message] 失败原因。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
