class_name AmethystWallet
extends RefCounted

var _balance: int


## 接收已由玩家聚合确认且关闭领取凭据的任务奖励。
## [param amount] 权威规则计算的正整数紫晶。
func credit_reward(amount: int) -> void:
	assert(amount > 0)
	_balance += amount


## 从权威存档恢复紫晶；默认零，不提供充值或兑换入口。
## [param saved_balance] 已通过持久化边界校验的非负余额。
func _init(saved_balance: int = 0) -> void:
	_balance = maxi(0, saved_balance)


## 查询只读紫晶余额。
## 返回当前可消费紫晶数。
func balance() -> int:
	return _balance


## 检查价格是否合法且余额足够。
## [param price] 来自服务端商品目录的售价。
## 返回购买能力或明确拒绝原因。
func can_spend(price: int) -> DomainResult:
	if price <= 0:
		return DomainResult.failure(&"commerce.invalid_price", "invalid premium price")
	if _balance < price:
		return DomainResult.failure(&"commerce.insufficient_amethyst", "not enough amethyst")
	return DomainResult.ok()


## 在玩家事务内扣除紫晶，不允许透支。
## [param price] 服务端已确认的商品价格。
## 返回扣款结果。
func spend(price: int) -> DomainResult:
	var checked := can_spend(price)
	if not checked.is_ok:
		return checked
	_balance -= price
	return DomainResult.ok()
