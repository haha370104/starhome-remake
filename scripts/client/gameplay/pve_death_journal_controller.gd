class_name PveDeathJournalController
extends Node

var journal := PveDeathJournal.new()
var _world: ActiveWorldController
var _window: PveDeathJournalPanel
var _character_id := ""
var _map_names: Dictionary[String, String] = {}


## 在会话开始前订阅权威战斗事件和角色身份，记录不依赖是否打开智脑窗口。
## [param presenter] 当前会话事件入口。[param panels] 唯一玩家投影。
## [param world] 当前地图定义。[param window] 只读展示与清除入口。
func configure(presenter: HallMultiplayerPresenter, panels: PlayerPanelSession, world: ActiveWorldController, window: PveDeathJournalPanel) -> void:
	_world = world
	_window = window
	panels.player_changed.connect(_player_changed)
	presenter.combat_event_received.connect(_record)
	presenter.combat_snapshot_received.connect(_snapshot)
	presenter.map_joined.connect(_map_joined)
	window.clear_requested.connect(_clear)
	_player_changed(panels.current_player)


## 按真实角色身份延迟加载个人日志，初始空投影不能与其他角色共用文件。
## [param player] 权威面板还原后的角色。
func _player_changed(player: Player) -> void:
	if player == null: return
	var identity := String(player.entity_id)
	if identity.is_empty() or identity == _character_id: return
	_character_id = identity
	var loaded := journal.open("user://pve-deaths-%s.cfg" % identity.sha256_text().left(16))
	if loaded != OK: _window.notice_requested.emit("本地击毁记录读取失败")
	_window.apply_entries(journal.entries())


## 读取快照中的短事件窗口，日志自身按服务端击毁身份去重。
## [param snapshot] 当前地图战斗快照。
func _snapshot(snapshot: Dictionary) -> void:
	for event: Dictionary in snapshot.get("recent_events", []): _record(event)


## 将自己被击毁的权威事实写入本地记录，不从客户端生命推测伤害来源。
## [param event] 实际战斗事件，其他玩家或非击毁事件会被拒绝。
func _record(event: Dictionary) -> void:
	var instance := String(event.get("death_map_instance_id", "未知地图"))
	var map_name := String(_map_names.get(instance, instance))
	if not journal.record(event, _character_id, map_name): return
	if journal.save() != OK: _window.notice_requested.emit("击毁记录写入失败，本次会话仍可查看")
	_window.apply_entries(journal.entries())


## 记住权威地图身份对应的名称，迟到的旧地图事件不能套用当前地图名。
## [param map_id] 业务地图身份。[param instance] 权威实例。[param _spawn] 出生位置。[param _version] 地图版本。
func _map_joined(map_id: StringName, instance: String, _spawn: Vector2, _version: int) -> void:
	_map_names[instance] = String(_world.definition.display_name) \
		if _world.definition != null and _world.definition.map_id == map_id else String(map_id)


## 清除已经由窗口确认的当前角色本地记录，写盘失败时保留列表。
func _clear() -> void:
	if journal.clear() != OK: _window.notice_requested.emit("击毁记录清除失败")
	_window.apply_entries(journal.entries())
