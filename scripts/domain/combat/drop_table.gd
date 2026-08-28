class_name DropTable
extends RefCounted

var _entries: Array[Dictionary] = []


## 初始化服务端已确认的怪物掉落表。
## [param raw_entries] 配置中的掉落数组；null 表示尚无可信掉落数据。
## 设计：未经确认的旧客户端候选表达式不得进入本对象。
func _init(raw_entries: Variant = null) -> void:
	if raw_entries is Array:
		for raw_entry: Variant in raw_entries:
			if raw_entry is Dictionary:
				_entries.append(raw_entry.duplicate(true))


## 查询当前是否存在可由权威服务器结算的掉落。
## 返回至少有一条可信配置时为 true。
func is_configured() -> bool:
	return not _entries.is_empty()


## 导出只读掉落配置副本。
## 返回掉落条目数组。
func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)
