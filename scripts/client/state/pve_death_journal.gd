class_name PveDeathJournal
extends RefCounted

const LIMIT := 100
var _entries: Array[Dictionary] = []
var _seen: Array[String] = []
var _path := ""


## 绑定当前角色本地日志文件，不接触游戏存档和奖励。
## [param path] 当前角色专属路径；测试使用隔离目录。
## 返回文件读取结果，不存在时为空日志。
func open(path: String) -> Error:
	_path = path
	_entries.clear()
	_seen.clear()
	var config := ConfigFile.new()
	var loaded := config.load(path)
	if loaded == ERR_FILE_NOT_FOUND: return OK
	if loaded != OK: return loaded
	var rows: Variant = config.get_value("journal", "entries", [])
	if not rows is Array or rows.size() > LIMIT: return ERR_INVALID_DATA
	var seen: Dictionary = {}
	var candidate: Array[Dictionary] = []
	for row: Variant in rows:
		if not _valid(row) or seen.has(row.id): return ERR_INVALID_DATA
		seen[row.id] = true
		candidate.append(row.duplicate(true))
	var identities: Variant = config.get_value("journal", "seen", seen.keys())
	if not identities is Array or identities.size() > LIMIT * 2: return ERR_INVALID_DATA
	for identity: Variant in identities:
		if not identity is String or identity.is_empty() or identity.length() > 256: return ERR_INVALID_DATA
	for row in candidate:
		if not identities.has(row.id): return ERR_INVALID_DATA
	_entries.assign(candidate)
	_seen.assign(identities)
	return OK


## 仅记录服务端确认的本角色PVE击毁，同一事件跨重复快照只记一次。
## [param event] 权威击毁事件。[param character_id] 当前角色身份。[param map_name] 当前地图可读名称。
## 返回是否新增记录；调用者负责报告保存错误。
func record(event: Dictionary, character_id: String, map_name: String) -> bool:
	if String(event.get("event_type", "")) != "monster_attack_resolved" \
		or character_id.is_empty() or String(event.get("target_entity_id", "")) != character_id \
		or not bool(event.get("target_destroyed", false)) or String(event.get("death_id", "")).is_empty(): return false
	if _seen.has(String(event.death_id)): return false
	var row := {"id": String(event.death_id), "time": int(event.get("death_time", 0)),
		"map": map_name, "source": String(event.get("attacker_display_name", "未知来源")),
		"position": event.get("impact_position", [0, 0]), "damage": int(event.get("damage", 0)),
		"cause": "毒雾持续伤害" if bool(event.get("corrosion_pulse", false)) else "怪物攻击"}
	if not _valid(row): return false
	_entries.push_front(row.duplicate(true))
	_seen.push_front(row.id)
	if _seen.size() > LIMIT * 2: _seen.pop_back()
	if _entries.size() > LIMIT: _entries.pop_back()
	return true


## 保存日志偏好文件，失败不清除当前会话的记录。
## 返回实际写入结果。
func save() -> Error:
	if _path.is_empty(): return ERR_UNCONFIGURED
	var config := ConfigFile.new()
	config.set_value("journal", "entries", _entries)
	config.set_value("journal", "seen", _seen)
	return config.save(_path)


## 清除本角色日志，写盘失败时保留原记录，避免误报删除成功。
## 返回清除是否持久化成功。
func clear() -> Error:
	var previous := _entries.duplicate(true)
	_entries.clear()
	var result := save()
	if result != OK: _entries.assign(previous)
	return result


## 读取最新在前的独立展示数据，窗口不能修改内部记录。
## 返回日志副本。
func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


## 校验本地文件中的有限数值和文本，拒绝非法对象或坐标。
## [param value] 单条序列化记录。
## 返回是否可安全加载与显示。
func _valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key: String in ["id", "map", "source", "cause"]:
		if not value.get(key) is String or String(value[key]).length() > 256: return false
	if value.id.is_empty(): return false
	for key: String in ["time", "damage"]:
		if not value.get(key) is int or int(value[key]) < 0: return false
	if not value.get("position") is Array or value.position.size() != 2: return false
	for coordinate: Variant in value.position:
		if not coordinate is int and not coordinate is float: return false
		if not is_finite(float(coordinate)): return false
	return true
