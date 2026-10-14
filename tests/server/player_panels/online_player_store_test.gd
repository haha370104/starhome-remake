extends SceneTree

var checks := 0
var failures := 0


## 验证同身份复用、局部事务隔离和同版本成长不会被缓存掩盖。
func _initialize() -> void:
	var fixture := PlayerPanelServiceFixture.new()
	_expect(fixture.initialize().is_ok, "初始化")
	var service: AuthoritativePlayerPanelService = fixture._service
	var state: PlayerStateRecord = fixture._state
	var store := OnlinePlayerStore.new(PlayerStateMapper.new(service.item_catalog()))
	var player: Player = store.observe(state).value
	var equipment := player.vehicle.loadout.items()[0]
	var item := player.inventory.items()[0]
	_expect(store.observe(state).value == player, "相同状态保留聚合身份")
	var changed := state.duplicate_record()
	changed.character_skills.driving.current_exp += 1
	var observed: Player = store.observe(changed).value
	_expect(observed == player and observed.skills.to_dictionary() == changed.character_skills, "同 revision 经验更新")
	_expect(observed.vehicle.loadout.items()[0] == equipment, "经验变化不重建装备")
	_expect(observed.inventory.items()[0] == item, "经验变化不重建背包")
	var before: Dictionary = PlayerStateMapper.new(service.item_catalog()).to_record(player).value.to_dictionary()
	var transaction: Player = PlayerTransaction.inventory_candidate(player, service.item_catalog()).value
	_expect(transaction.inventory.items()[0] != item, "背包写集合物品隔离")
	_expect(transaction.vehicle != player.vehicle and transaction.vehicle.loadout == player.vehicle.loadout, "车辆状态隔离且只读装配复用")
	var scoped := PlayerInventoryRecordWriter.capture(transaction, changed)
	var full := PlayerStateMapper.new(service.item_catalog()).to_record(transaction)
	var canonical := PlayerStateMapper.new(service.item_catalog()).to_domain(scoped.value)
	var canonical_record := PlayerStateMapper.new(service.item_catalog()).to_record(canonical.value)
	_expect(canonical_record.value.to_dictionary() == full.value.to_dictionary(), "写集合采集与完整映射语义等价，兼容旧式空状态")
	var partial: Player = PlayerTransaction.inventory_candidate(player, service.item_catalog(), [item.instance_id]).value
	for other: GameItem in player.inventory.items():
		_expect((partial.inventory.find(other.instance_id) != other) == (other.instance_id == item.instance_id), "仅隔离物品写集合")
	transaction.inventory.items()[0].quantity = 3
	transaction.vehicle.health = 1
	_expect(PlayerStateMapper.new(service.item_catalog()).to_record(player).value.to_dictionary() == before, "候选未提交不泄漏")
	var expected_bundle := service.build_bundle(state)
	var failed := service.execute(state, {"type": "move_inventory_item", "instance_id": item.instance_id,
		"position_px": [50000, 50000], "inventory_revision": state.inventory_revision})
	_expect(not failed.is_ok, "无效背包事务拒绝")
	_expect(service.build_bundle(state).inventory == expected_bundle.inventory, "拒绝后在线投影正确")
	var bad := state.duplicate_record()
	bad.inventory_stacks[0].item_definition_id = "does_not_exist"
	_expect(not store.observe(bad).is_ok, "无效恢复拒绝")
	_expect(store.observe(changed).value == player, "无效恢复不覆盖旧聚合")
	store.forget(state.character_id)
	_expect(store.observe(state).value != player, "退出后重新恢复新聚合")
	_test_dirty_capture(fixture._state)
	print("ONLINE_PLAYER_STORE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


## 记录领域断言。
## [param valid] 条件。[param description] 失败说明。
func _expect(valid: bool, description: String) -> void:
	checks += 1
	if not valid:
		failures += 1
		push_error(description)


## 验证无变化跳过保存、同版本变化持久化和旧候选拒绝。
## [param initial] 旧存档语义的合法初始记录。
func _test_dirty_capture(initial: PlayerStateRecord) -> void:
	var repo := FilePlayerStateRepository.new("user://online-write-set-test.json")
	_expect(repo.initialize().is_ok, "隔离仓储初始化")
	var saves := AuthoritativeAutosaveService.new()
	saves.configure(repo)
	var registered := saves.register_player(initial)
	_expect(registered.is_ok, "登记角色")
	var id := initial.character_id
	var revision := saves.state_for(id).revision
	saves.save_player(id, func(state: PlayerStateRecord) -> DomainResult: return DomainResult.ok(state))
	_expect(saves.state_for(id).revision == revision and saves.save_count == 0, "无脏数据不产生版本")
	var old := saves.state_for(id)
	var changed := old.duplicate_record()
	changed.character_skills.driving.current_exp += 2
	saves.update_runtime_state(id, changed)
	saves.save_player(id, func(state: PlayerStateRecord) -> DomainResult: return DomainResult.ok(state))
	_expect(repo.load_player(id).value.character_skills == changed.character_skills, "同版本运行期技能被保存")
	_expect(saves.commit_player_state(id, old).error_code == &"persistence.revision_conflict", "旧候选不得覆盖新事务")
	var current := saves.state_for(id)
	var result := saves.save_player(id, func(state: PlayerStateRecord) -> DomainResult:
		var newer := saves.state_for(id)
		newer.currency += 7
		saves.commit_player_state(id, newer)
		return DomainResult.ok(state))
	_expect(not result.is_ok and saves.state_for(id).currency == current.currency + 7, "采集重入不覆盖已提交事务")
	repo.close()
