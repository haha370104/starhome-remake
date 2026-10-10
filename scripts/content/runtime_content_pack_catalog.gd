class_name RuntimeContentPackCatalog
extends RefCounted

var content_version := ""
var errors: PackedStringArray = []
var _packs: Dictionary = {}
var _mounted: Dictionary = {}


## 读取受控内容清单。资源包已经物化到统一的 assets/ 根目录。
## [param path] 调用方传入的 `path` 参数。
## 返回该函数计算、查询或操作得到的结果。
func load_file(path: String) -> bool:
	errors.clear()
	_packs.clear()
	_mounted.clear()
	if not FileAccess.file_exists(path):
		_add_error("catalog", "内容包目录不存在：%s" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_add_error("catalog", "内容包目录必须是 JSON object")
		return false
	if int(parsed.get("schema_version", 0)) != 1:
		_add_error("schema_version", "只支持 schema_version=1")
	content_version = String(parsed.get("content_version", "")).strip_edges()
	if content_version.is_empty():
		_add_error("content_version", "内容版本不能为空")
	var entries: Variant = parsed.get("packs", [])
	if not entries is Array:
		_add_error("packs", "packs 必须是 array")
		return false
	for index in range(entries.size()):
		_load_pack_entry(entries[index], index)
	return errors.is_empty()


## 注册清单中的全部内容组。资源已经位于 res://assets/，不再挂载 ZIP。
## 返回全部内容组是否注册成功。
func mount_all() -> bool:
	for pack_id_value in _packs:
		if not mount_pack(StringName(pack_id_value)):
			return false
	return true


## 注册指定内容组；重复调用是幂等的。
## [param pack_id] 调用方传入的 `pack_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func mount_pack(pack_id: StringName) -> bool:
	if _mounted.has(pack_id):
		return true
	if not _packs.has(pack_id):
		_add_error("pack", "未知内容包：%s" % pack_id)
		return false
	var entry: Dictionary = _packs[pack_id]
	var content_root := String(entry.get("path", "res://assets/")).strip_edges()
	if not content_root.begins_with("res://assets/"):
		_add_error("pack", "内容组必须位于 res://assets/：%s" % pack_id)
		return false
	var absolute_root := ProjectSettings.globalize_path(content_root)
	if not DirAccess.dir_exists_absolute(absolute_root):
		_add_error("pack", "物化内容根目录不存在：%s" % content_root)
		return false
	_mounted[pack_id] = true
	return true


## 执行 `pack_ids` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func pack_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for pack_id_value in _packs:
		result.append(StringName(pack_id_value))
	return result


## 查询 `is_mounted` 对应的模块状态。
## [param pack_id] 调用方传入的 `pack_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func is_mounted(pack_id: StringName) -> bool:
	return _mounted.has(pack_id)


## 执行 `pack_entry` 对应的模块操作。
## [param pack_id] 调用方传入的 `pack_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func pack_entry(pack_id: StringName) -> Dictionary:
	return _packs.get(pack_id, {}).duplicate(true)


## 加载并校验 `load_pack_entry` 对应的模块数据。
## [param value] 调用方传入的 `value` 参数。
## [param index] 调用方传入的 `index` 参数。
func _load_pack_entry(value: Variant, index: int) -> void:
	var prefix := "packs[%d]" % index
	if not value is Dictionary:
		_add_error(prefix, "内容包条目必须是 object")
		return
	var entry: Dictionary = value.duplicate(true)
	var pack_id := StringName(String(entry.get("pack_id", "")).strip_edges())
	if pack_id.is_empty() or not _is_business_id(String(pack_id)):
		_add_error(prefix + ".pack_id", "内容包 ID 必须是小写业务标识")
		return
	if _packs.has(pack_id):
		_add_error(prefix + ".pack_id", "内容包 ID 重复：%s" % pack_id)
		return
	var pack_path := String(entry.get("path", "res://assets/")).strip_edges()
	if not pack_path.begins_with("res://assets/"):
		_add_error(prefix + ".path", "内容组必须位于 res://assets/")
		return
	entry["path"] = pack_path
	_packs[pack_id] = entry


## 执行 `is_business_id` 对应的模块操作。
## [param value] 调用方传入的 `value` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _is_business_id(value: String) -> bool:
	if value.is_empty():
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true


## 执行 `add_error` 对应的模块操作。
## [param field] 调用方传入的 `field` 参数。
## [param message] 调用方传入的 `message` 参数。
func _add_error(field: String, message: String) -> void:
	errors.append("%s: %s" % [field, message])
