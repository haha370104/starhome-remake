class_name GroundItemService
extends RefCounted

var _autosave: AuthoritativeAutosaveService
var _repository: PlayerStateRepository
var _panels: AuthoritativePlayerPanelService
var _catalog: ItemCatalog
var _mapper: PlayerStateMapper
var _records: Dictionary[String, GroundItemRecord] = {}
var _snapshots: Dictionary = {}


## 注入权威聚合、存储和物品映射，恢复地面实例的只读索引。
## [param autosave] 在线玩家事务入口。[param repository] 与玩家共享检查点的仓储。
## [param panels] 完整面板投影服务。[param catalog] 现有物品目录。
func _init(autosave: AuthoritativeAutosaveService, repository: PlayerStateRepository, panels: AuthoritativePlayerPanelService, catalog: ItemCatalog) -> void:
	_autosave = autosave
	_repository = repository
	_panels = panels
	_catalog = catalog
	_mapper = PlayerStateMapper.new(catalog)
	_reload()


## 查询拾取意图是否属于玩家丢弃的持久化物品。
## [param loot_id] 地面身份。
## 返回是否由本服务拥有。
func has_item(loot_id: String) -> bool:
	return _records.has(loot_id)


## 编排整件丢弃，地图负责可达性，领域负责物品资格，仓储负责共同提交。
## [param state] 已采集实时资源的玩家记录。[param map] 当前权威地图。
## [param command] 只允许物品编号、版本和可选落点的操作意图。
## 返回提交后的面板与地面事件，失败不改变任何所有权。
func drop(state: PlayerStateRecord, map: AuthoritativeMapInstance, command: Dictionary) -> DomainResult:
	var entity: AuthoritativeEntity = map.entities.get(state.character_id) if map != null else null
	if entity == null or map.navigation == null:
		return DomainResult.failure(&"loot.map_unavailable", "当前地图不可用")
	var target := entity.position
	if command.has("position"):
		var point: Variant = command.position
		if not point is Array or point.size() != 2:
			return DomainResult.failure(&"loot.invalid_payload", "丢弃坐标无效")
		for value: Variant in point:
			if not (value is int or value is float) or not is_finite(float(value)):
				return DomainResult.failure(&"loot.invalid_payload", "丢弃坐标无效")
		target = Vector2(float(point[0]), float(point[1]))
	if not map.navigation.is_walkable(target) or not map.navigation.segment_is_walkable(entity.position, target):
		return DomainResult.failure(&"loot.drop_blocked", "不能把物品丢到障碍物上或墙后")
	var restored := _mapper.to_domain(state)
	if not restored.is_ok: return restored
	var player: Player = restored.value
	var dropped := GroundItem.drop_from(player, String(command.get("instance_id", "")),
		int(command.get("inventory_revision", -1)), map.instance_id, entity.position, target)
	if not dropped.is_ok: return dropped
	var record := GroundItemRecord.from_domain(dropped.value)
	if not record.is_ok: return record
	var candidate := _mapper.to_record(player)
	if not candidate.is_ok: return candidate
	var committed := _autosave.commit_ground_transfer(candidate.value, record.value)
	if not committed.is_ok: return committed
	_reload()
	var bundle := _panels.build_bundle(committed.value)
	bundle["item_dropped"] = (dropped.value as GroundItem).snapshot()
	return DomainResult.ok(bundle)


## 在同一事务中完成完整实例入包与地面移除，重复拾取不会再次入账。
## [param state] 已采集的玩家记录。[param map] 当前权威地图。[param loot_id] 地面身份。
## 返回拾取事件和同事务面板；背包满、距离错误或落盘失败保持原状态。
func pickup(state: PlayerStateRecord, map: AuthoritativeMapInstance, loot_id: String) -> DomainResult:
	var record: GroundItemRecord = _records.get(loot_id)
	var entity: AuthoritativeEntity = map.entities.get(state.character_id) if map != null else null
	if record == null or entity == null:
		return DomainResult.failure(&"loot.not_found", "物品已经不存在")
	var restored := _mapper.to_domain(state)
	if not restored.is_ok: return restored
	var recovered := record.to_domain(_catalog)
	if not recovered.is_ok: return recovered
	var dropped: GroundItem = recovered.value
	var accepted := dropped.receive_into(restored.value, map.instance_id, entity.position)
	if not accepted.is_ok: return accepted
	var candidate := _mapper.to_record(restored.value)
	if not candidate.is_ok: return candidate
	var committed := _autosave.commit_ground_transfer(candidate.value, null, loot_id)
	if not committed.is_ok: return committed
	_reload()
	return DomainResult.ok({"loot_event": {"event_type": "loot_picked_up", "loot_id": loot_id,
		"item_definition_id": dropped.item.definition_id, "quantity": dropped.item.quantity,
		"actor_id": state.character_id}, "panel_bundle": _panels.build_bundle(committed.value)})


## 为地图提供缓存的地面表现数据，不逐帧反序列化装备成长。
## [param map_instance_id] 地图稳定实例身份。
## 返回独立的展示数组，调用方不能改写缓存。
func snapshots(map_instance_id: String) -> Array:
	if not _snapshots.has(map_instance_id):
		var result: Array[Dictionary] = []
		for record: GroundItemRecord in _records.values():
			if record.map_instance_id != map_instance_id: continue
			result.append({"loot_id": record.loot_id, "map_instance_id": map_instance_id,
				"position": [record.position.x, record.position.y], "item_definition_id": record.item.item_definition_id,
				"quantity": record.item.quantity, "dropped_by_player": true})
		_snapshots[map_instance_id] = result
	return _snapshots[map_instance_id].duplicate(true)


## 仅在共同提交成功后刷新只读索引，仓储仍是所有权的唯一来源。
func _reload() -> void:
	_records.clear()
	_snapshots.clear()
	for record: GroundItemRecord in _repository.ground_items():
		_records[record.loot_id] = record
