class_name AiDecisionProvider
extends Node

signal completed(request_id: int, result: DomainResult)


## 异步请求一次决策；实现不得阻塞模拟线程。
## [param request_id] 模块生成的请求号。[param observation] 有限观察。[param context] 自身目标和有限记忆。
func decide(request_id: int, observation: Dictionary, context: Dictionary) -> void:
	_emit_deferred.call_deferred(request_id, DomainResult.failure(&"ai.provider_missing", "未配置决策提供器"))
	# 保留契约参数，具体实现消费观察和上下文。
	if observation.is_empty() and context.is_empty(): return


## 取消在途请求；关闭后不得继续发布旧决策。
func cancel() -> void:
	pass


## 将同步产生的结果延后到模块完成登记之后发布。
## [param request_id] 请求号。[param result] 决策结果。
func _emit_deferred(request_id: int, result: DomainResult) -> void:
	completed.emit(request_id, result)
