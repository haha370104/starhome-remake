class_name MiningCatalog
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const JsonConfigLoader := preload("res://scripts/core/json_config_loader.gd")
const DEFAULT_PATH := "res://data/gameplay/mining_v1.json"

var content_version := ""
var defaults: Dictionary = {}
var _minerals: Dictionary = {}
var _maps: Dictionary = {}


## 读取默认荣耀版矿物目录与复刻刷新策略。
static func load_default() -> DomainResult:
	return load_file(DEFAULT_PATH)


## 读取并校验指定矿物配置。
static func load_file(path: String) -> DomainResult:
	var loaded := JsonConfigLoader.load_dictionary(path)
	if not loaded.is_ok:
		return loaded
	var catalog := MiningCatalog.new()
	var configured := catalog._configure(loaded.value)
	return DomainResult.ok(catalog) if configured.is_ok else configured


## 返回地图的完整矿源策略；非采矿地图返回空字典。
func policy_for_map(map_id: String) -> Dictionary:
	var map_value: Variant = _maps.get(map_id)
	if not map_value is Dictionary or not bool(map_value.get("enabled", false)):
		return {}
	var policy := defaults.duplicate(true)
	policy.merge((map_value as Dictionary).duplicate(true), true)
	return policy


## 按稳定矿物标识返回定义副本。
func mineral(mineral_id: String) -> Dictionary:
	var value: Variant = _minerals.get(mineral_id)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func mineral_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for mineral_id: String in _minerals:
		result.append(mineral_id)
	result.sort()
	return result


func map_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for map_id: String in _maps:
		result.append(map_id)
	result.sort()
	return result


## 依据权重和全局生成序号确定性选择本轮矿种。
func mineral_for_spawn(map_id: String, sequence: int) -> DomainResult:
	var policy := policy_for_map(map_id)
	if policy.is_empty() or sequence < 0:
		return DomainResult.failure(&"mining.map_disabled", "map has no mining population policy")
	var pool: Array = policy.get("mineral_pool", [])
	var total_weight := 0.0
	for raw_entry: Variant in pool:
		total_weight += float((raw_entry as Dictionary).get("weight", 0.0)) \
			if raw_entry is Dictionary else 0.0
	if total_weight <= 0.0:
		return DomainResult.failure(&"mining.invalid_pool", "mineral pool has no positive weight")
	var random := RandomNumberGenerator.new()
	random.seed = hash("%s.mineral.%d" % [map_id, sequence])
	var roll := random.randf() * total_weight
	for raw_entry: Variant in pool:
		if not raw_entry is Dictionary:
			continue
		roll -= float(raw_entry.get("weight", 0.0))
		if roll <= 0.0:
			return DomainResult.ok(mineral(String(raw_entry.get("mineral_id", ""))))
	return DomainResult.ok(mineral(String((pool.back() as Dictionary).get("mineral_id", ""))))


func _configure(document: Dictionary) -> DomainResult:
	if int(document.get("schema_version", -1)) != 1:
		return DomainResult.failure(&"mining.invalid_catalog", "unsupported mining schema")
	content_version = String(document.get("content_version", ""))
	var defaults_value: Variant = document.get("defaults")
	var minerals_value: Variant = document.get("minerals")
	var maps_value: Variant = document.get("maps")
	if content_version.is_empty() or not defaults_value is Dictionary \
			or not minerals_value is Array or not maps_value is Dictionary:
		return DomainResult.failure(&"mining.invalid_catalog", "mining catalog sections are invalid")
	defaults = (defaults_value as Dictionary).duplicate(true)
	for key: String in [
		"maximum_sources", "source_capacity", "replenish_interval_seconds",
		"collection_interval_seconds", "minimum_collection_distance",
		"maximum_collection_distance", "selection_radius", "minimum_spawn_separation",
		"yield_per_cycle", "iron_equivalent_per_level",
	]:
		if float(defaults.get(key, 0.0)) <= 0.0:
			return DomainResult.failure(&"mining.invalid_catalog", "mining default is not positive: %s" % key)
	if float(defaults["minimum_collection_distance"]) >= float(defaults["maximum_collection_distance"]):
		return DomainResult.failure(&"mining.invalid_catalog", "mining distance bounds are inverted")
	for raw_definition: Variant in minerals_value:
		if not raw_definition is Dictionary:
			return DomainResult.failure(&"mining.invalid_catalog", "mineral definition must be an object")
		var definition: Dictionary = raw_definition
		var mineral_id := String(definition.get("id", ""))
		var collectible := bool(definition.get("collectible", true))
		if mineral_id.is_empty() or _minerals.has(mineral_id) \
				or (collectible and String(definition.get("item_definition_id", "")).is_empty()) \
				or int(definition.get("required_mining_level", -1)) < 0 \
				or float(definition.get("experience_coefficient", 0.0)) <= 0.0:
			return DomainResult.failure(&"mining.invalid_catalog", "mineral definition is invalid")
		_minerals[mineral_id] = definition.duplicate(true)
	_maps = (maps_value as Dictionary).duplicate(true)
	for raw_map_id: Variant in _maps:
		var map_policy: Variant = _maps[raw_map_id]
		if not map_policy is Dictionary or not map_policy.get("mineral_pool") is Array:
			return DomainResult.failure(&"mining.invalid_catalog", "map mineral policy is invalid")
		for raw_entry: Variant in map_policy["mineral_pool"]:
			if not raw_entry is Dictionary or not _minerals.has(String(raw_entry.get("mineral_id", ""))) \
					or float(raw_entry.get("weight", 0.0)) <= 0.0:
				return DomainResult.failure(&"mining.invalid_catalog", "map mineral pool entry is invalid")
	return DomainResult.ok(self)
