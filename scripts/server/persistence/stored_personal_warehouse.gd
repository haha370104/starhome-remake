class_name StoredPersonalWarehouse
extends PersonalWarehouse

var _saved: PersonalWarehouseRecord
var _catalog: ItemCatalog
var _loaded := false
var _load_error: DomainResult = null


## 保留不可变仓库快照，人物战斗和食品计算无需构造柜内全部装备。
## [param saved] 仓储边界已验证且之后不再修改的记录。
## [param catalog] 首次实际访问时还原物品使用的统一目录。
func _init(saved: PersonalWarehouseRecord, catalog: ItemCatalog) -> void:
	_saved = saved
	_catalog = catalog
	revision = saved.revision()
	_cabinets.clear()


## 读取轻量柜数，不加载柜内物品。
## 返回已开通的柜数。
func cabinet_count() -> int:
	return super() if _loaded else _saved.cabinet_count()


## 第一次访问时构造独立的可变领域物品，失败保留原快照并向存取服务返回错误。
## 返回还原结果；重复调用不重复加载。
func materialize() -> DomainResult:
	if _loaded: return DomainResult.ok()
	if _load_error != null: return _load_error
	var result := _saved.materialize(_catalog)
	if not result.is_ok:
		_load_error = result
		return result
	_cabinets = result.value._cabinets
	_loaded = true
	return DomainResult.ok()


## 在仓库未访问时保留同一个不可变快照，避免每秒重建和复制数百件装备。
## 返回可共享的只读快照；已经加载或修改后返回空值，保存流程需捕获新事实。
func unchanged_record() -> PersonalWarehouseRecord:
	return _saved if not _loaded and revision == _saved.revision() else null
