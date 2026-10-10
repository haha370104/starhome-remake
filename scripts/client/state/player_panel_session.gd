class_name PlayerPanelSession
extends RefCounted

signal command_dispatched(command: Dictionary)
signal bundle_received(bundle: Dictionary)
signal player_changed(player: Player)
signal inventory_changed(player: Player, item_ids: Array[String])
signal journal_changed(entries: Array)
signal progression_changed(player: Player, change: PlayerChange)
signal attributes_changed(player: Player)
signal equipment_changed(player: Player)
signal panel_state_changed(state: PanelState, change: Variant)

var current_player: CurrentPlayer
var state: PanelState
var _dispatcher: Callable
var _bundle: Dictionary = {}
var _sync_id := ""
var _resync_pending := false
var _notification_pending := false
var _changed_item_ids: Dictionary[String, bool] = {}
var _journal_notification_pending := false
var _equipment_notification_pending := false
var _pending_progression := PlayerChange.new()


## 建立独立于窗口生命周期的玩家投影和命令边界。
## [param dispatcher] 提交纯命令的传输无关回调。
## [param catalog] 世界与窗口共享的物品目录。
func _init(dispatcher: Callable, catalog: ItemCatalog = null) -> void:
	_dispatcher = dispatcher
	current_player = CurrentPlayer.new(catalog)
	state = PanelState.new()


## 应用权威消息并通知各展示订阅者；查询专用消息不覆盖玩家状态。
## [param bundle] 权威面板、商店、制造或在线玩家消息。
func apply_bundle(bundle: Dictionary) -> void:
	if bundle.get("player_change") is Dictionary:
		apply_change(bundle.player_change)
		if _resync_pending or int(bundle.player_change.get("transaction_revision", -1)) != current_player.revision: return
	if bundle.has("sync_id") and String(bundle.sync_id) != _sync_id: return
	if bundle.has("transaction_revision") and int(bundle.transaction_revision) < current_player.revision: return
	if bundle.has("character"):
		if String(bundle.get("sync_id", "")) != _sync_id: return
		if int(bundle.get("transaction_revision", -1)) < current_player.revision and not _bundle.is_empty(): return
	var player_updated := current_player.apply_bundle(bundle) if bundle.has("character") else false
	if bundle.has("character") and not player_updated:
		_request_sync()
		return
	if player_updated:
		_changed_item_ids.clear()
		_pending_progression = PlayerChange.new()
		_journal_notification_pending = false
		_equipment_notification_pending = false
		_bundle = bundle.duplicate(true)
		state.replace_bundle(_bundle)
		_resync_pending = false
		panel_state_changed.emit(state, null)
	bundle_received.emit(bundle)
	if player_updated:
		player_changed.emit(current_player)


## 获取当前同事务面板投影，供新打开的展示订阅者初始化。
## 返回快照副本；尚未收到玩家快照时为空。
func snapshot_bundle() -> Dictionary:
	return state.snapshot_bundle()


## 获取当前只读面板状态对象；窗口只消费其中的领域快照。
func panel_state() -> PanelState:
	return state


## 为面板意图补齐权威 revision 后提交，始终复制以保护调用方数据。
## [param command] 尚未补齐人物或战车版本的操作意图。
func dispatch(command: Dictionary) -> void:
	var payload := command.duplicate(true)
	if payload.erase("requires_loadout_revision") and _bundle.get("vehicle") is Dictionary:
		payload["loadout_revision"] = int(_bundle["vehicle"].get("revision", -1))
	if payload.erase("requires_state_revision"):
		payload["state_revision"] = int(_bundle.get("transaction_revision", -1))
	command_dispatched.emit(payload.duplicate(true))
	if _dispatcher.is_valid():
		_dispatcher.call(payload)


## 新握手开始新的同步世代，迟到的旧会话消息不能写入此玩家。
## [param sync_id] 权威握手中的会话标识。
func begin_sync(sync_id: String) -> void:
	_sync_id = sync_id
	_changed_item_ids.clear()
	_pending_progression = PlayerChange.new()
	_journal_notification_pending = false
	_equipment_notification_pending = false
	_bundle.clear()
	state.clear()
	_resync_pending = false
	current_player.revision = -1


## 应用玩家组件增量，版本断档时只请求一次完整同步。
## [param payload] 来自传输边界的变更值。
func apply_change(payload: Dictionary) -> void:
	if String(payload.get("sync_id", "")) != _sync_id: return
	var parsed := PlayerChange.parse(payload)
	if not parsed.is_ok:
		_request_sync()
		return
	var change: PlayerChange = parsed.value
	if change.revision <= current_player.revision: return
	if _resync_pending: return
	if _bundle.is_empty() or change.base_revision != current_player.revision or not current_player.apply_change(change):
		_request_sync()
		return
	_bundle.transaction_revision = change.revision
	if not change.character.is_empty(): _bundle.character = change.character.duplicate(true)
	if not change.vehicle.is_empty():
		_equipment_notification_pending = _equipment_notification_pending or change.vehicle.revision != _bundle.vehicle.revision
		_bundle.vehicle = change.vehicle.duplicate(true)
	_bundle.character.revision = change.revision
	if change.inventory_revision >= 0: _bundle.inventory.revision = change.inventory_revision
	if change.inventory_currency >= 0: _bundle.inventory.currency = change.inventory_currency
	var rows: Array = _bundle.inventory.items
	for identity: String in change.removed_items:
		_changed_item_ids[identity] = true
		for index in range(rows.size() - 1, -1, -1):
			if rows[index].instance_id == identity: rows.remove_at(index)
	for item: Dictionary in change.items:
		_changed_item_ids[String(item.instance_id)] = true
		var found := false
		for index in rows.size():
			if rows[index].instance_id == item.instance_id:
				rows[index] = item
				found = true
				break
		if not found: rows.append(item)
	_bundle.inventory.item_count = rows.size()
	var journal: Array = _bundle.get("mission_journal", [])
	for entry: Dictionary in change.quests:
		var visible := bool(entry.get("accepted", false)) or int(entry.get("completions", 0)) > 0
		var found := false
		for index in range(journal.size()):
			if journal[index].task_id == entry.task_id:
				if visible:
					journal[index] = entry
				else:
					journal.remove_at(index)
				found = true
				break
		if not found and visible: journal.append(entry)
	_bundle["mission_journal"] = journal
	for skill: Dictionary in change.skills:
		for index in _bundle.character.skills.size():
			if _bundle.character.skills[index].id == skill.id: _bundle.character.skills[index] = skill
	if change.level >= 0: _bundle.character.level = change.level
	if not change.achievements.is_empty():
		_bundle.achievements = current_player.achievements.network_snapshot()
		_bundle.character.achievement_title = _bundle.achievements.title_name
	if not change.daily.is_empty(): _bundle.daily_activities = change.daily
	if not change.food.is_empty(): _bundle.food_status = change.food
	if change.character_health >= 0: _bundle.character.health = change.character_health
	if not change.presets.is_empty():
		_bundle.vehicle_presets = change.presets
		_bundle.preset_server_time = change.preset_server_time
	if change.attributes_changed: _bundle.vehicle.stats = current_player.calculate_vehicle_stats()
	if not change.vehicle_stats.is_empty(): _bundle.vehicle.stats = change.vehicle_stats
	state.replace_bundle(_bundle)
	_pending_progression.merge(change)
	_journal_notification_pending = _journal_notification_pending or not change.quests.is_empty()
	if not _notification_pending:
		_notification_pending = true
		_flush_notifications.call_deferred()


## 同帧多次入账只刷新一次相关界面，领域状态已在接收时立即提交。
func _flush_notifications() -> void:
	_notification_pending = false
	if _bundle.is_empty(): return
	var item_ids := _changed_item_ids.keys()
	_changed_item_ids.clear()
	var progression := _pending_progression
	_pending_progression = PlayerChange.new()
	var equipment_updated := _equipment_notification_pending or not progression.character.is_empty()
	_equipment_notification_pending = false
	panel_state_changed.emit(state, progression)
	if progression.inventory_revision >= 0: inventory_changed.emit(current_player, item_ids)
	progression_changed.emit(current_player, progression)
	if equipment_updated: equipment_changed.emit(current_player)
	if progression.attributes_changed: attributes_changed.emit(current_player)
	if _journal_notification_pending:
		_journal_notification_pending = false
		journal_changed.emit(_bundle.get("mission_journal", []))


## 版本断档后通过已有查询入口恢复完整状态，不重复发送同步请求。
func _request_sync() -> void:
	if _resync_pending: return
	_resync_pending = true
	dispatch({"type": "query"})


## 初次打开核心面板时按需同步；已有权威状态时不重复查询。
## [param force] 显式失效时即使状态已就绪也重新请求。
func request_full_sync(force: bool = false) -> void:
	if force: _resync_pending = false
	if not force and current_player.is_ready(): return
	_request_sync()


## 标记当前投影失效并发起一次新的完整同步。
func invalidate_full_sync() -> void:
	request_full_sync(true)
