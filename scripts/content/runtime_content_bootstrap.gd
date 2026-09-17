class_name RuntimeContentBootstrap
extends RefCounted

const PackCatalogScript := preload("res://scripts/content/runtime_content_pack_catalog.gd")
const DEFAULT_CATALOG_PATHS := [
	"res://data/content/glory_map_content_packs_v1.json",
	"res://data/content/glory_sprite_content_packs_v1.json",
	"res://data/content/glory_monster_palette_content_pack_v1.json",
	"res://data/content/glory_mine_palette_content_pack_v1.json",
	"res://data/content/recovered_content_packs_v1.json",
]

static var _mounted := false
static var _catalogs: Array = []


## 在任何定义或素材查找前挂载荣耀版运行内容；同一进程只执行一次。
## 返回该函数计算、查询或操作得到的结果。
static func mount_default() -> Dictionary:
	if _mounted:
		return {"ok": true, "catalog_count": _catalogs.size()}
	_catalogs.clear()
	for catalog_path in DEFAULT_CATALOG_PATHS:
		var catalog = PackCatalogScript.new()
		if not catalog.load_file(catalog_path):
			return {"ok": false, "message": "; ".join(catalog.errors)}
		if not catalog.mount_all(false):
			return {"ok": false, "message": "; ".join(catalog.errors)}
		_catalogs.append(catalog)
	_mounted = true
	return {"ok": true, "catalog_count": _catalogs.size()}


## 查询 `is_mounted` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
static func is_mounted() -> bool:
	return _mounted
