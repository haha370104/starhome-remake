class_name SqliteDriverPort
extends RefCounted



## 判断 `is_available` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func is_available() -> bool:
	return false


## 执行 `open_database` 对应的模块操作。
## [param database_path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func open_database(database_path: String) -> DomainResult:
	return DomainResult.failure(&"persistence.sqlite_driver_unavailable", "no SQLite driver is installed")


## 执行 `execute` 对应的模块操作。
## [param sql] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param parameters] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func execute(sql: String, parameters: Array = []) -> DomainResult:
	return DomainResult.failure(&"persistence.sqlite_driver_unavailable", "no SQLite driver is installed")


## 执行 `query` 对应的模块操作。
## [param sql] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param parameters] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func query(sql: String, parameters: Array = []) -> DomainResult:
	return DomainResult.failure(&"persistence.sqlite_driver_unavailable", "no SQLite driver is installed")


## 执行 `begin_immediate` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func begin_immediate() -> DomainResult:
	return execute("BEGIN IMMEDIATE")


## 执行 `commit` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func commit() -> DomainResult:
	return execute("COMMIT")


## 执行 `rollback` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func rollback() -> DomainResult:
	return execute("ROLLBACK")


## 执行 `runtime_capability` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
static func runtime_capability() -> Dictionary:
	var known_classes: Array[StringName] = []
	for candidate: StringName in [&"SQLite", &"SQLiteDatabase", &"SQLiteStatement", &"SQLite3"]:
		if ClassDB.class_exists(candidate):
			known_classes.append(candidate)
	return {
		"available": not known_classes.is_empty() or Engine.has_singleton("SQLite") or Engine.has_singleton("SQLite3"),
		"known_classes": known_classes,
		"known_singleton": Engine.has_singleton("SQLite") or Engine.has_singleton("SQLite3"),
		"adapter_status": &"driver_adapter_required",
	}
