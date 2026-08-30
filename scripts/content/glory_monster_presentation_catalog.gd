class_name GloryMonsterPresentationCatalog
extends RefCounted

const DEFAULT_PATH := "res://data/gameplay/glory/glory_monsters_v1.json"

var errors := PackedStringArray()
var _by_actor_id: Dictionary = {}


## 读取生成的怪物目录，只保留客户端表现所需的 actor 到 ALE 引用映射。
## 返回该函数计算、查询或操作得到的结果。
func load_default() -> bool:
	errors.clear()
	_by_actor_id.clear()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		errors.append("荣耀怪物表现目录格式无效")
		return false
	for raw_definition: Variant in parsed.get("definitions", []):
		if not raw_definition is Dictionary:
			continue
		var definition: Dictionary = raw_definition
		var actor_id := String(definition.get("combat_actor_id", ""))
		var presentation: Variant = definition.get("presentation", {})
		if actor_id.is_empty() or not presentation is Dictionary:
			continue
		_by_actor_id[actor_id] = (presentation as Dictionary).duplicate(true)
	return not _by_actor_id.is_empty()


## 执行 `definition_for_actor` 对应的模块操作。
## [param actor_id] 调用方传入的 `actor_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func definition_for_actor(actor_id: String) -> Dictionary:
	var value: Variant = _by_actor_id.get(actor_id)
	return value.duplicate(true) if value is Dictionary else {}


## 执行 `size` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func size() -> int:
	return _by_actor_id.size()
