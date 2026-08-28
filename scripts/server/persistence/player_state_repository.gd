class_name PlayerStateRepository
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")


## 配置并初始化 `initialize` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func initialize() -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository initialize is not implemented")


## 执行 `create_player` 对应的模块操作。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func create_player(state: PlayerStateRecord) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository create is not implemented")


## 执行 `load_player` 对应的模块操作。
## [param character_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func load_player(character_id: String) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository load is not implemented")


## 执行 `save_player` 对应的模块操作。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param expected_revision] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func save_player(state: PlayerStateRecord, expected_revision: int) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository save is not implemented")


## 执行 `transact_player` 对应的模块操作。
## [param character_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param operation] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func transact_player(character_id: String, operation: Callable) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository transaction is not implemented")


## 执行 `current_schema_version` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func current_schema_version() -> int:
	return 0
