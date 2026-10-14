class_name AiWorldPort
extends RefCounted


## 经权威入口创建独立角色。
## [param _key] 稳定插件身份。
## 返回AiPlayerActor或失败。
func open_actor(_key: String) -> DomainResult:
	return DomainResult.failure(&"ai.port_unavailable", "AI世界端口未连接")


## 获取当前角色的有限可见状态。
## [param _actor] 本模块拥有的会话。
## 返回AiPlayerObservation或失败。
func observe(_actor: AiPlayerActor) -> DomainResult:
	return DomainResult.failure(&"ai.port_unavailable", "AI世界端口未连接")


## 提交移动意图，位置由正式导航裁决。
## [param _actor] 会话。[param _target] 世界目标。
## 返回权威移动结果。
func move(_actor: AiPlayerActor, _target: Vector2) -> DomainResult:
	return DomainResult.failure(&"ai.port_unavailable", "AI世界端口未连接")


## 提交一次已验证行动，不开放通用服务定位或状态写入。
## [param _actor] 会话。[param _action] 受限行动。[param _target] 当前观察目标，可为空。
## 返回权威结果。
func perform(_actor: AiPlayerActor, _action: AiPlayerAction, _target: AiPlayerObservation.Target) -> DomainResult:
	return DomainResult.failure(&"ai.port_unavailable", "AI世界端口未连接")


## 正常保存并释放模块自己的角色，不操作人类会话。
## [param _actor] 本模块拥有的会话。
## 返回清理状态，失败时不能伪报保存成功。
func close_actor(_actor: AiPlayerActor) -> DomainResult:
	return DomainResult.failure(&"ai.port_unavailable", "AI世界端口未连接")
