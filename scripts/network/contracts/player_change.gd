class_name PlayerChange
extends RefCounted

const VERSION := 1
const ROW_PATHS := {"inventory/items": "instance_id", "character/skills": "id", "mission_journal": "id"}


## 比较两份完整投影，仅编码变化字段与有稳定身份的物品、技能行。
## [param before] 上一已发送投影。[param after] 当前投影。[param path] 内部字段路径。
## 返回递归补丁；删除、空数组与空字典均有明确语义。
static func difference(before: Dictionary, after: Dictionary, path: String = "") -> Dictionary:
	var result := {"set": {}, "remove": [], "children": {}, "rows": {}}
	for key: String in before:
		if not after.has(key): result.remove.append(key)
	for key: String in after:
		if before.has(key) and before[key] == after[key]: continue
		var child_path: String = key if path.is_empty() else path + "/" + key
		if before.get(key) is Dictionary and after[key] is Dictionary:
			result.children[key] = difference(before[key], after[key], child_path)
		elif ROW_PATHS.has(child_path) and before.get(key) is Array and after[key] is Array \
				and _index(before[key], ROW_PATHS[child_path]).is_ok and _index(after[key], ROW_PATHS[child_path]).is_ok:
			var id_key: String = ROW_PATHS[child_path]
			var old: Dictionary = _index(before[key], id_key).value
			var changed: Array = []
			var order: Array = []
			for row: Dictionary in after[key]:
				order.append(row[id_key])
				if old.get(row[id_key]) != row: changed.append(row.duplicate(true))
			result.rows[key] = {"id_key": id_key, "order": order, "changed": changed}
		else:
			result.set[key] = after[key]
	return result.duplicate(true)


## 在隔离字典上校验并合入补丁，失败不会改变基线。
## [param before] 当前完整投影。[param patch] 来自可靠链路的补丁。[param path] 内部字段路径。
## 返回候选投影或格式错误。
static func apply(before: Dictionary, patch: Dictionary, path: String = "") -> DomainResult:
	if not patch.get("set") is Dictionary or not patch.get("remove") is Array \
			or not patch.get("children") is Dictionary or not patch.get("rows") is Dictionary:
		return _invalid()
	var result := before.duplicate(true)
	var touched: Dictionary = {}
	for section: String in ["remove", "set", "children", "rows"]:
		for key: Variant in patch[section]:
			if not key is String or touched.has(key): return _invalid()
			touched[key] = true
			match section:
				"remove": result.erase(key)
				"set": result[key] = patch.set[key]
				"children":
					if not result.get(key) is Dictionary or not patch.children[key] is Dictionary: return _invalid()
					var child := apply(result[key], patch.children[key], key if path.is_empty() else path + "/" + key)
					if not child.is_ok: return child
					result[key] = child.value
				"rows":
					var child_path: String = key if path.is_empty() else path + "/" + key
					if not ROW_PATHS.has(child_path) or not result.get(key) is Array or not patch.rows[key] is Dictionary: return _invalid()
					var rows := _apply_rows(result[key], patch.rows[key], ROW_PATHS[child_path])
					if not rows.is_ok: return rows
					result[key] = rows.value
	return DomainResult.ok(result.duplicate(true))


## 合入变化行并按权威顺序重建，缺失、重复或未被引用的新增行一律拒绝。
## [param before] 旧行数组。[param patch] 行补丁。[param id_key] 协议固定的身份字段。
## 返回完整行数组或错误。
static func _apply_rows(before: Array, patch: Dictionary, id_key: String) -> DomainResult:
	if patch.get("id_key") != id_key or not patch.get("order") is Array or not patch.get("changed") is Array: return _invalid()
	var old := _index(before, id_key)
	var changes := _index(patch.changed, id_key)
	if not old.is_ok or not changes.is_ok: return _invalid()
	var rows: Dictionary = old.value
	rows.merge(changes.value, true)
	var seen: Dictionary = {}
	var result: Array = []
	for id: Variant in patch.order:
		if not id is String or seen.has(id) or not rows.has(id): return _invalid()
		seen[id] = true
		result.append(rows[id])
	for id: String in changes.value:
		if not seen.has(id): return _invalid()
	return DomainResult.ok(result)


## 建立稳定行身份索引并拒绝重复身份。
## [param rows] 完整行数组。[param id_key] 身份字段。
## 返回身份到行的映射或错误。
static func _index(rows: Array, id_key: String) -> DomainResult:
	var result: Dictionary = {}
	for row: Variant in rows:
		if not row is Dictionary or not row.get(id_key) is String or String(row[id_key]).is_empty() or result.has(row[id_key]): return _invalid()
		result[row[id_key]] = row
	return DomainResult.ok(result)


## 生成统一的无副作用协议错误。
## 返回补丁格式错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"player_sync.invalid", "玩家增量格式无效")

