class_name DamageFloatPool
extends Node

const MAX_IDLE := 128
var _world: Node2D
var _idle: Array[CombatDamageFloat] = []
var _active: Dictionary[CombatDamageFloat, bool] = {}


## 绑定效果所属世界；池和世界由同一场景生命周期持有。
## [param world] 飘字父节点。
func configure(world: Node2D) -> void:
	_world = world


## 取出空闲飘字；仍在播放的效果不会被回收或覆盖。
## 返回已加入世界的可复用节点。
func take() -> CombatDamageFloat:
	var view: CombatDamageFloat
	if not _idle.is_empty():
		view = _idle.pop_back()
		PerformanceTelemetry.increment(&"damage_float_pool_hit")
	else:
		view = CombatDamageFloat.new()
		_world.add_child(view)
		view.finished.connect(_recycle)
	_active[view] = true
	return view


## 已结束动画归还池，空闲容量超限时释放。
## [param view] 完成一次表现的节点。
func _recycle(view: CombatDamageFloat) -> void:
	_active.erase(view)
	if _idle.size() < MAX_IDLE: _idle.append(view)
	else: view.queue_free()


## 清除当前世界全部飘字及旧动画回调。
func clear() -> void:
	for view: CombatDamageFloat in _active.keys() + _idle:
		if is_instance_valid(view):
			view.cancel()
			view.queue_free()
	_active.clear()
	_idle.clear()


## 控制器提前退出时同步停止池内效果。
func _exit_tree() -> void:
	clear()
