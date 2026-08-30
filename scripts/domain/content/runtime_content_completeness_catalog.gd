class_name RuntimeContentCompletenessCatalog
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const DEFAULT_PATH := "res://data/content/glory_runtime_content_manifest_v1.json"

var content_version := ""
var source_policy: Dictionary = {}
var _catalogs: Dictionary = {}
var _exceptions: Array[Dictionary] = []


## 加载并校验 `load_default` 对应的模块数据。
## 返回该函数计算、查询或操作得到的结果。
static func load_default() -> DomainResult:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		return DomainResult.failure(&"content.coverage_invalid", "runtime content coverage is invalid")
	var catalog = load("res://scripts/domain/content/runtime_content_completeness_catalog.gd").new()
	catalog.content_version = String(parsed.get("content_version", ""))
	catalog.source_policy = (parsed.get("source_policy", {}) as Dictionary).duplicate(true)
	catalog._catalogs = (parsed.get("operational_catalogs", {}) as Dictionary).duplicate(true)
	for value: Variant in parsed.get("explicit_exceptions", []):
		if value is Dictionary:
			catalog._exceptions.append((value as Dictionary).duplicate(true))
	if catalog.content_version.is_empty() or catalog._catalogs.is_empty():
		return DomainResult.failure(&"content.coverage_invalid", "runtime content coverage is incomplete")
	return DomainResult.ok(catalog)


## 执行 `catalog_summary` 对应的模块操作。
## [param kind] 调用方传入的 `kind` 参数。
## 返回该函数计算、查询或操作得到的结果。
func catalog_summary(kind: String) -> Dictionary:
	var value: Variant = _catalogs.get(kind)
	return value.duplicate(true) if value is Dictionary else {}


## 执行 `exceptions` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func exceptions() -> Array[Dictionary]:
	return _exceptions.duplicate(true)


## 执行 `exception` 对应的模块操作。
## [param kind] 调用方传入的 `kind` 参数。
## 返回该函数计算、查询或操作得到的结果。
func exception(kind: String) -> Dictionary:
	for value: Dictionary in _exceptions:
		if value.get("kind") == kind:
			return value.duplicate(true)
	return {}
