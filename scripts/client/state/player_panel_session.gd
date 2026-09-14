class_name PlayerPanelSession
extends RefCounted

signal command_dispatched(command: Dictionary)
signal bundle_received(bundle: Dictionary)
signal player_changed(player: Player)

var current_player: CurrentPlayer
var _dispatcher: Callable
var _bundle: Dictionary = {}


## 建立独立于窗口生命周期的玩家投影和命令边界。
## [param dispatcher] 提交纯命令的传输无关回调。
## [param catalog] 世界与窗口共享的物品目录。
func _init(dispatcher: Callable, catalog: ItemCatalog = null) -> void:
	_dispatcher = dispatcher
	current_player = CurrentPlayer.new(catalog)


## 应用权威消息并通知各展示订阅者；查询专用消息不覆盖玩家状态。
## [param bundle] 权威面板、商店、制造或在线玩家消息。
func apply_bundle(bundle: Dictionary) -> void:
	var player_updated := current_player.apply_bundle(bundle)
	if player_updated:
		_bundle = current_player.snapshot_bundle()
	bundle_received.emit(bundle)
	if player_updated:
		player_changed.emit(current_player)


## 获取当前同事务面板投影，供新打开的展示订阅者初始化。
## 返回快照副本；尚未收到玩家快照时为空。
func snapshot_bundle() -> Dictionary:
	return _bundle.duplicate(true)


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
