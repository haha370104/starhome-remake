class_name TimedPopulationQuota
extends RefCounted

var maximum_population := 0
var interval_ticks := 0
var next_refresh_tick := -1


## 校验定时补足策略，初始时刻立即开放首次补足。
## [param policy] JSON 边界中的数量上限和秒数；空配置表示关闭。
## [param simulation_hz] 每秒权威模拟刻数。
## 返回配置结果；无效配置不会留下可用的刷新计划。
func configure(policy: Dictionary, simulation_hz: int) -> DomainResult:
	maximum_population = 0
	interval_ticks = 0
	next_refresh_tick = -1
	if policy.is_empty():
		return DomainResult.ok(self)
	var maximum := int(policy.get("maximum_population", 0))
	var seconds := float(policy.get("replenish_interval_seconds", 0.0))
	if maximum <= 0 or not is_finite(seconds) or seconds <= 0.0 or simulation_hz <= 0:
		return DomainResult.failure(&"combat.invalid_population_quota", "定时种群上限或周期无效")
	maximum_population = maximum
	interval_ticks = maxi(1, roundi(seconds * simulation_hz))
	next_refresh_tick = 0
	return DomainResult.ok(self)


## 在到期时领取本轮补量；跳过休眠中的空轮次，保持原周期相位。
## [param current_tick] 单调递增的地图权威时钟。
## [param alive_count] 本种群当前存活数量，不包含其他种群。
## 返回需要补足的数量，同一时刻重复调用不会再次发放。
## 设计：长时间休眠只补缺口，不累积历史批次，也不突破上限。
func take_due_replenishment(current_tick: int, alive_count: int) -> int:
	if next_refresh_tick < 0 or current_tick < next_refresh_tick:
		return 0
	var elapsed_intervals := floori(float(current_tick - next_refresh_tick) / interval_ticks) + 1
	next_refresh_tick += elapsed_intervals * interval_ticks
	return maxi(0, maximum_population - maxi(0, alive_count))


## 查询当前时刻是否需要计算种群缺口。
## [param current_tick] 地图权威时钟。
## 返回到期且已启用时为真，避免每帧扫描种群。
func is_due(current_tick: int) -> bool:
	return next_refresh_tick >= 0 and current_tick >= next_refresh_tick
