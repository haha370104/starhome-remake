class_name MonsterViewPool
extends RefCounted

const MAX_IDLE := 64
var _idle: Array[MonsterWorldView] = []


## 按表现类型复用已配置节点，避免把不同怪物的精灵和碰撞形状混用。
## [param actor] 原表现身份。
## 返回匹配空闲节点或 null。
func take(actor: String) -> MonsterWorldView:
	for index in range(_idle.size() - 1, -1, -1):
		var view := _idle[index]
		if not is_instance_valid(view):
			_idle.remove_at(index)
		elif view.combat_actor_id == actor:
			_idle.remove_at(index)
			PerformanceTelemetry.increment(&"monster_pool_hit")
			return view
	return null


## 清除实体状态后保留有限节点；超出预算的节点正常释放。
## [param view] 已移出活动实体索引的怪物视图。
func recycle(view: MonsterWorldView) -> void:
	view.reset_for_pool()
	if _idle.size() >= MAX_IDLE: view.queue_free()
	else: _idle.append(view)


## 切图或控制器销毁时释放池内所有节点。
func clear() -> void:
	for view: MonsterWorldView in _idle:
		if is_instance_valid(view): view.queue_free()
	_idle.clear()
