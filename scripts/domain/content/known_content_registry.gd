class_name KnownContentRegistry
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const DEFAULT_MANIFEST_PATH := "res://data/content/known_content_registry_v1.json"
const SUPPORTED_SCHEMA_VERSION := 1
const SUPPORTED_KINDS := [&"map", &"monster", &"item"]
const ALLOWED_RUNTIME_STATES := [&"ready", &"unimplemented"]
const ALLOWED_PRESENTATION_STATES := [
	&"ready",
	&"partial",
	&"unimplemented",
	&"source_relation_only",
	&"source_references_known",
	&"unknown",
]

var content_version := ""
var _definitions_by_id: Dictionary = {}
var _ids_by_kind: Dictionary = {}
var _runtime_index: Dictionary = {}
var _legacy_index: Dictionary = {}
var _summary_by_kind: Dictionary = {}


## 从受控默认 manifest 加载全量已知内容注册表。
static func load_default() -> DomainResult:
	return load_manifest(DEFAULT_MANIFEST_PATH)


## 加载 manifest 及其固定的地图、怪物和道具目录。
## “已知”注册不等于运行时可实例化；availability 字段必须明确表达边界。
static func load_manifest(manifest_path: String) -> DomainResult:
	if not _is_controlled_path(manifest_path):
		return DomainResult.failure(
			&"content_registry.path_not_allowed",
			"known-content manifest is outside the controlled data root",
		)
	var manifest_result := _read_dictionary(manifest_path)
	if not manifest_result.is_ok:
		return manifest_result
	var manifest: Dictionary = manifest_result.value
	if int(manifest.get("schema_version", -1)) != SUPPORTED_SCHEMA_VERSION:
		return DomainResult.failure(
			&"content_registry.unsupported_schema",
			"known-content manifest schema is unsupported",
		)
	var catalogs_value: Variant = manifest.get("catalogs")
	if not catalogs_value is Dictionary:
		return DomainResult.failure(
			&"content_registry.invalid_manifest", "manifest catalogs must be a dictionary"
		)
	var registry = load("res://scripts/domain/content/known_content_registry.gd").new()
	registry.content_version = String(manifest.get("content_version", ""))
	if registry.content_version.is_empty():
		return DomainResult.failure(
			&"content_registry.invalid_manifest", "manifest content version is missing"
		)
	var expected_counts: Dictionary = manifest.get("expected_counts", {})
	for kind: StringName in SUPPORTED_KINDS:
		var path := String((catalogs_value as Dictionary).get(String(kind), ""))
		if not _is_controlled_path(path):
			return DomainResult.failure(
				&"content_registry.path_not_allowed",
				"known-content catalog is outside the controlled data root",
			)
		var loaded: Variant = registry._load_catalog(
			kind, path, expected_counts.get(String(kind), {})
		)
		if not loaded.is_ok:
			return loaded
	var links: Variant = registry._validate_cross_catalog_links()
	return DomainResult.ok(registry) if links.is_ok else links


## 按全局稳定注册 ID 查询一条已知内容定义。
func definition(registration_id: String) -> Dictionary:
	var value: Variant = _definitions_by_id.get(registration_id)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


## 返回某类全部定义，按注册 ID 稳定排序。
func definitions_for(kind: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for registration_id: String in _ids_by_kind.get(kind, []):
		result.append((_definitions_by_id[registration_id] as Dictionary).duplicate(true))
	return result


## 查询一个现有 remake runtime_id 对应的全部来源注册。
## 地图允许多个世界分支共同映射到同一业务 MapDefinition。
func registrations_for_runtime(kind: StringName, runtime_id: String) -> Array[Dictionary]:
	return _definitions_for_ids(_runtime_index.get(kind, {}).get(runtime_id, []))


## 按旧客户端索引、类名、中文名或 runtime_key 查询来源注册。
## 同名与重复类定义合法，因此返回数组而不是任意挑选一个。
func registrations_for_legacy_key(kind: StringName, legacy_key: String) -> Array[Dictionary]:
	return _definitions_for_ids(_legacy_index.get(kind, {}).get(legacy_key, []))


## 返回生成器写入并经加载器核验的目录摘要。
func summary_for(kind: StringName) -> Dictionary:
	var value: Variant = _summary_by_kind.get(kind)
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


## 返回三类目录合计定义数。
func size() -> int:
	return _definitions_by_id.size()


func _load_catalog(kind: StringName, path: String, expected: Variant) -> DomainResult:
	var document_result := _read_dictionary(path)
	if not document_result.is_ok:
		return document_result
	var document: Dictionary = document_result.value
	if int(document.get("schema_version", -1)) != SUPPORTED_SCHEMA_VERSION \
			or String(document.get("content_version", "")) != content_version \
			or StringName(document.get("catalog_kind", "")) != kind:
		return DomainResult.failure(
			&"content_registry.catalog_mismatch",
			"known-content catalog header does not match its manifest",
		)
	var definitions_value: Variant = document.get("definitions")
	if not definitions_value is Array:
		return DomainResult.failure(
			&"content_registry.invalid_catalog", "catalog definitions must be an array"
		)
	var expected_dictionary: Dictionary = expected if expected is Dictionary else {}
	if int(expected_dictionary.get("definitions", -1)) != definitions_value.size():
		return DomainResult.failure(
			&"content_registry.count_mismatch", "catalog definition count does not match manifest"
		)
	_ids_by_kind[kind] = []
	_runtime_index[kind] = {}
	_legacy_index[kind] = {}
	for raw_definition: Variant in definitions_value:
		if not raw_definition is Dictionary:
			return DomainResult.failure(
				&"content_registry.invalid_definition", "registration must be a dictionary"
			)
		var definition: Dictionary = (raw_definition as Dictionary).duplicate(true)
		var registration_id := String(definition.get("id", ""))
		var availability_value: Variant = definition.get("availability")
		if registration_id.is_empty() or _definitions_by_id.has(registration_id) \
				or not availability_value is Dictionary:
			return DomainResult.failure(
				&"content_registry.invalid_definition",
				"registration ID is empty/duplicated or availability is missing",
			)
		var availability: Dictionary = availability_value
		if StringName(availability.get("registration", "")) != &"known" \
				or StringName(availability.get("runtime", "")) not in ALLOWED_RUNTIME_STATES \
				or StringName(availability.get("presentation", "")) \
				not in ALLOWED_PRESENTATION_STATES:
			return DomainResult.failure(
				&"content_registry.invalid_availability", "registration availability is invalid"
			)
		var runtime_ids_value: Variant = definition.get("runtime_ids", [])
		var legacy_keys_value: Variant = definition.get("legacy_keys", [])
		if not runtime_ids_value is Array or not legacy_keys_value is Array:
			return DomainResult.failure(
				&"content_registry.invalid_definition", "registration indexes must be arrays"
			)
		if StringName(availability["runtime"]) == &"ready" and runtime_ids_value.is_empty():
			return DomainResult.failure(
				&"content_registry.invalid_availability",
				"runtime-ready registration must map to a runtime ID",
			)
		_definitions_by_id[registration_id] = definition
		(_ids_by_kind[kind] as Array).append(registration_id)
		for runtime_value: Variant in runtime_ids_value:
			_index_append(_runtime_index[kind], String(runtime_value), registration_id)
		for legacy_value: Variant in legacy_keys_value:
			_index_append(_legacy_index[kind], String(legacy_value), registration_id)
	(_ids_by_kind[kind] as Array).sort()
	_summary_by_kind[kind] = (document.get("summary", {}) as Dictionary).duplicate(true)
	return DomainResult.ok()


func _validate_cross_catalog_links() -> DomainResult:
	for definition: Dictionary in definitions_for(&"monster"):
		for presence_value: Variant in definition.get("map_presence", []):
			if not presence_value is Dictionary \
					or not _definitions_by_id.has(String(presence_value.get("map_id", ""))):
				return DomainResult.failure(
					&"content_registry.unresolved_map_relation",
					"monster map presence references an unknown registered map",
				)
		for archetype_value: Variant in definition.get("map_archetype_ids", []):
			if not _definitions_by_id.has(String(archetype_value)):
				return DomainResult.failure(
					&"content_registry.unresolved_monster_archetype",
					"monster row references an unknown map archetype",
				)
	return DomainResult.ok()


func _definitions_for_ids(ids: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not ids is Array:
		return result
	for registration_id: String in ids:
		result.append((_definitions_by_id[registration_id] as Dictionary).duplicate(true))
	return result


static func _index_append(index: Dictionary, key: String, registration_id: String) -> void:
	if key.is_empty():
		return
	if not index.has(key):
		index[key] = []
	(index[key] as Array).append(registration_id)


static func _read_dictionary(path: String) -> DomainResult:
	if not FileAccess.file_exists(path):
		return DomainResult.failure(
			&"content_registry.file_missing", "known-content file does not exist: %s" % path
		)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return DomainResult.failure(
			&"content_registry.invalid_json", "known-content file root must be a dictionary"
		)
	return DomainResult.ok(parsed)


static func _is_controlled_path(path: String) -> bool:
	return path.begins_with("res://data/content/") \
		and path.ends_with(".json") \
		and not path.contains("..")
