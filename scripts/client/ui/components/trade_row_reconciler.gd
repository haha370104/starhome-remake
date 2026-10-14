class_name TradeRowReconciler
extends RefCounted


## 按稳定物品身份复用未变化的行，避免刷新打断按钮悬浮与滚动。
## [param container] 商品行容器。[param entries] 权威商品投影。
## [param mode] 买入或卖出模式。[param factory] 单行构造回调。
## 返回是否替换了行；调用者据此更新详情区。
static func reconcile(container: VBoxContainer, entries: Array, mode: String, factory: Callable) -> bool:
	var existing: Dictionary = {}
	for child in container.get_children():
		existing[String(child.get_meta("trade_key", ""))] = child
	var changed := false
	var index := 0
	for entry: Dictionary in entries:
		var identity := String(entry.get("definition_id" if mode == "buy" else "instance_id", ""))
		var key := mode + ":" + identity
		var row: Control = existing.get(key)
		existing.erase(key)
		if row != null and row.get_meta("trade_entry", {}) != entry:
			container.remove_child(row)
			row.queue_free()
			row = null
		if row == null:
			row = factory.call(entry)
			row.set_meta("trade_key", key)
			row.set_meta("trade_entry", entry.duplicate(true))
			container.add_child(row)
			changed = true
		if row.get_index() != index:
			container.move_child(row, index)
		index += 1
	for row: Control in existing.values():
		container.remove_child(row)
		row.queue_free()
		changed = true
	return changed
