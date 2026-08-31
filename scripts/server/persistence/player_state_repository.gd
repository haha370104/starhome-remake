class_name PlayerStateRepository
extends RefCounted



## 配置并初始化 `initialize` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func initialize() -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository initialize is not implemented")


## 执行 `create_player` 对应的模块操作。
## [param _state] 子类实现时使用的待创建角色状态；基类只返回未实现错误。
## 返回该函数计算、查询或操作得到的结果。
func create_player(_state: PlayerStateRecord) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository create is not implemented")


## 执行 `load_player` 对应的模块操作。
## [param _character_id] 子类实现时使用的角色标识；基类只返回未实现错误。
## 返回该函数计算、查询或操作得到的结果。
func load_player(_character_id: String) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository load is not implemented")


## 执行 `save_player` 对应的模块操作。
## [param _state] 子类实现时使用的待保存角色状态。
## [param _expected_revision] 子类实现时校验的乐观锁版本。
## 返回该函数计算、查询或操作得到的结果。
func save_player(_state: PlayerStateRecord, _expected_revision: int) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository save is not implemented")


## 执行 `transact_player` 对应的模块操作。
## [param _character_id] 子类实现时使用的角色标识。
## [param _operation] 子类事务内执行的角色操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func transact_player(_character_id: String, _operation: Callable) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository transaction is not implemented")


## 执行 `current_schema_version` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func current_schema_version() -> int:
	return 0
