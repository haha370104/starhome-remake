class_name RuntimeContentBootstrap
extends RefCounted

const PackCatalogScript := preload("res://scripts/content/runtime_content_pack_catalog.gd")
const DEFAULT_CATALOG_PATH := "res://data/content/glory_map_content_packs_v1.json"

static var _mounted := false
static var _catalog


## 在任何定义或素材查找前挂载荣耀版运行内容；同一进程只执行一次。
static func mount_default() -> Dictionary:
	if _mounted:
		return {"ok": true, "content_version": _catalog.content_version}
	var catalog = PackCatalogScript.new()
	if not catalog.load_file(DEFAULT_CATALOG_PATH):
		return {"ok": false, "message": "; ".join(catalog.errors)}
	if not catalog.mount_all(false):
		return {"ok": false, "message": "; ".join(catalog.errors)}
	_catalog = catalog
	_mounted = true
	return {"ok": true, "content_version": catalog.content_version}


static func is_mounted() -> bool:
	return _mounted
