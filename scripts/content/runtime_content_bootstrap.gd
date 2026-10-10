class_name RuntimeContentBootstrap
extends RefCounted

const PackCatalogScript := preload("res://scripts/content/runtime_content_pack_catalog.gd")
const RUNTIME_MANIFEST_PATH := "res://data/content/glory_runtime_content_manifest_v1.json"
const DEFAULT_CATALOG_PATHS := [
	"res://data/content/glory_map_content_packs_v1.json",
	"res://data/content/glory_sprite_content_packs_v1.json",
	"res://data/content/glory_monster_palette_content_pack_v1.json",
	"res://data/content/glory_mine_palette_content_pack_v1.json",
	"res://data/content/recovered_content_packs_v1.json",
]

static var _mounted := false
static var _catalogs: Array = []


## 在任何定义或素材查找前验证统一 assets 运行树；同一进程只执行一次。
## 返回该函数计算、查询或操作得到的结果。
static func mount_default() -> Dictionary:
	if _mounted:
		return {"ok": true, "catalog_count": _catalogs.size()}
	_catalogs.clear()
	var runtime_manifest_error := _validate_runtime_manifest()
	if not runtime_manifest_error.is_empty():
		return {"ok": false, "message": runtime_manifest_error}
	for catalog_path in DEFAULT_CATALOG_PATHS:
		var catalog = PackCatalogScript.new()
		if not catalog.load_file(catalog_path):
			return {"ok": false, "message": "; ".join(catalog.errors)}
		if not catalog.mount_all():
			return {"ok": false, "message": "; ".join(catalog.errors)}
		_catalogs.append(catalog)
	_mounted = true
	return {"ok": true, "catalog_count": _catalogs.size()}


## 只读取小型运行时覆盖清单；来源归档与物化审计由离线工具负责。
## 返回空字符串表示验证通过，否则返回可直接显示的错误。
static func _validate_runtime_manifest() -> String:
	if not FileAccess.file_exists(RUNTIME_MANIFEST_PATH):
		return "运行时内容清单不存在：%s" % RUNTIME_MANIFEST_PATH
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUNTIME_MANIFEST_PATH))
	if not parsed is Dictionary:
		return "运行时内容清单必须是 JSON object"
	if int(parsed.get("schema_version", 0)) != 1:
		return "不支持的运行时内容清单 schema_version"
	if String(parsed.get("content_version", "")).strip_edges().is_empty():
		return "运行时内容清单缺少 content_version"
	return ""


## 查询 `is_mounted` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
static func is_mounted() -> bool:
	return _mounted
