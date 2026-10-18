class_name ClientAudioBinding
extends Node

var audio := preload("res://scripts/client/gameplay/client_audio_controller.gd").new()
var _world: ActiveWorldController


## 在组合阶段接入已存在的事件，不参与战斗结算或持有额外玩家状态。
## [param world] 当前地图所有者。[param movement] 本地移动所有者。
## [param session] 玩法事件来源。[param panels] 当前玩家投影。
## [param listener] 世界音效监听位置。
## [param travel] 原子切图完成事件来源。
func configure(world: ActiveWorldController, movement: LocalPlayerController,
		session: HallMultiplayerPresenter, panels: PlayerPanelSession, listener: Node2D,
		travel: MapTravelController) -> void:
	_world = world
	add_child(audio)
	if not audio.configure(listener):
		return
	travel.map_committed.connect(_on_map_replaced)
	movement.movement_state_changed.connect(audio.set_moving)
	session.combat_snapshot_received.connect(audio.on_combat_snapshot)
	session.combat_event_received.connect(audio.on_combat_event)
	session.skill_level_up_received.connect(audio.on_skill_level_up)
	panels.player_changed.connect(audio.on_player_changed)
	audio.set_map(world.definition)
	audio.connect_ui_buttons()


## 原子切图完成后读取唯一当前地图并重置旧声音循环。
func _on_map_replaced() -> void:
	audio.set_map(_world.definition)
