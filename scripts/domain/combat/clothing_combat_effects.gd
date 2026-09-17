class_name ClothingCombatEffects
extends RefCounted

var repair_ready_tick := 0
var repair_wait_reduction := 0.0
var _weapon := ""
var _target := ""
var _hits := 0
var _last_hit_tick := -1000000


## 切换武器时清除连续命中，未命中也不能保留另一把武器的层数。
## [param weapon_id] 本次实际发射的武器定义。
func observe_weapon(weapon_id: String) -> void:
	if _weapon != weapon_id:
		reset_chain()
		_weapon = weapon_id


## 每次主目标命中至多计数一次，第四次返回额外伤害倍率。
## [param weapon_id] 弹体发射时的武器身份。
## [param target_id] 实际命中的主目标。
## [param tick] 权威命中时钟。
## [param hz] 模拟频率。
## [param bonus] 该弹体发射时的追击强度。
## 返回额外倍率；无特性、旧武器在途弹体或断链时不触发。
func hit(weapon_id: String, target_id: String, tick: int, hz: int, bonus: float) -> float:
	if bonus <= 0 or target_id.is_empty() or weapon_id != _weapon:
		return 0.0
	if _target != target_id or tick - _last_hit_tick > hz * 5:
		_hits = 0
	_target = target_id
	_last_hit_tick = tick
	_hits += 1
	if _hits == 4:
		_hits = 0
		return bonus
	return 0.0


## 受击推迟下一次可维修时刻，但不改变固定三秒维修周期。
## [param tick] 权威受击时钟。
## [param hz] 模拟频率。
func damaged(tick: int, hz: int) -> void:
	repair_ready_tick = tick + ceili((3.0 - clampf(repair_wait_reduction, 0, 1.2)) * hz)


## 死亡、目标死亡或换武器后清空追击层数。
func reset_chain() -> void:
	_target = ""
	_hits = 0
	_last_hit_tick = -1000000
