extends RefCounted

const MovementScript := preload("res://scripts/client/gameplay/local_player_controller.gd")

var _avatar: PlayerWorldAvatar
var _active := false


## 绑定本地战车表现；不生成采矿收益，也不自行判定采矿是否成功。
## [param avatar] 当前玩家世界表现节点。
func configure(avatar: PlayerWorldAvatar) -> void:
	_avatar = avatar


## 用权威动作快照驱动采掘臂八向循环，缺省或失效状态立即收起。
## [param snapshot] 含 local_mining 和 local_vehicle 的战斗快照。
## 设计：每次快照可重入，重复快照不重置动画时钟；不靠三秒产出事件猜动作状态。
func apply_snapshot(snapshot: Dictionary) -> void:
	if not is_instance_valid(_avatar):
		return
	var state: Dictionary = snapshot.get("local_mining", {})
	var target: Array = state.get("target_position", [])
	if not bool(state.get("active", false)) or target.size() != 2 \
			or not _avatar.is_combat_actor_active() \
			or int(snapshot.get("local_vehicle", {}).get("health", 0)) <= 0:
		clear()
		return
	var motion := Vector2(float(target[0]), float(target[1])) - _avatar.position
	var applied := _avatar.set_combat_layer_pose(
		&"primary_weapon", &"collect", MovementScript.direction_index(motion)
	)
	if not applied:
		clear()
		return
	_active = true


## 结束采矿局部姿态，移除朝向覆盖，让装置重新跟随车身。
func clear() -> void:
	if _active and is_instance_valid(_avatar):
		_avatar.clear_combat_layer_action(&"primary_weapon")
		_avatar.combat_presenter.clear_layer_direction(&"primary_weapon")
	_active = false
