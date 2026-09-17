class_name GloryMonsterPresentationCatalog
extends RefCounted

const DEFAULT_PATH := "res://data/gameplay/glory/glory_monsters_v1.json"
const IMPACT_PATH := "res://data/gameplay/glory/monster_hit_effects_v1.json"

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
		# npcinfo 的旧字段混有身体动画；只允许下面显式审计的命中目录提供效果。
		_by_actor_id[actor_id].erase("hit_effect")
	return not _by_actor_id.is_empty() and _load_impact_overrides()


## 应用经过原客户端调用链审计的命中素材，修正旧表中不可用的历史字段。
## 返回配置是否完整有效；未知怪物或重复覆盖会使加载失败。
## 设计：只消费显式映射，不按近似文件名寻找替代图，也不读取网络给出的资源路径。
func _load_impact_overrides() -> bool:
	var loaded := JsonConfigLoader.load_dictionary(IMPACT_PATH)
	if not loaded.is_ok or int(loaded.value.get("schema_version", 0)) != 1 \
		or not loaded.value.get("definitions") is Array \
		or not loaded.value.get("unresolved", []) is Array:
		errors.append("怪物命中特效目录格式无效")
		return false
	var seen: Dictionary = {}
	for raw: Variant in loaded.value.get("definitions", []):
		if not raw is Dictionary or not raw.get("combat_actor_ids") is Array:
			errors.append("命中特效必须声明怪物身份列表")
			return false
		for actor_value: Variant in raw.combat_actor_ids:
			var actor_id := String(actor_value)
			if not _by_actor_id.has(actor_id) or seen.has(actor_id):
				errors.append("命中特效怪物未知或重复：%s" % actor_id)
				return false
			seen[actor_id] = true
			if raw.has("hit_effect") and raw.hit_effect is String:
				_by_actor_id[actor_id]["hit_effect"] = raw.hit_effect
			elif raw.has("impact") and raw.impact is Dictionary:
				_by_actor_id[actor_id]["impact"] = raw.impact.duplicate(true)
			else:
				errors.append("命中特效缺少资源：%s" % actor_id)
				return false
	for raw: Variant in loaded.value.get("unresolved", []):
		if not raw is Dictionary:
			errors.append("待核实命中特效条目格式无效")
			return false
		var actor_id := String(raw.get("combat_actor_id", ""))
		if not _by_actor_id.has(actor_id) or seen.has(actor_id):
			errors.append("待核实命中特效怪物未知或重复：%s" % actor_id)
			return false
		seen[actor_id] = true
	return true


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
