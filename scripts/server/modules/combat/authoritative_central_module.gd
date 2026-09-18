class_name AuthoritativeCentralModule
extends RefCounted

var _random := RandomNumberGenerator.new()


## 初始化独立随机流，不让中枢判定改变掉落或普通伤害的随机顺序。
## [param seed_value] 当前地图确定性种子。
func reset(seed_value: int) -> void:
	_random.seed = seed_value


## 只为已接受的真实能量炮射击建立一次性判定，不为失败开火或副武器创建状态。
## [param controller] 角色芯片状态。[param rules] 规则。[param weapon] 权威武器定义。
## 返回本发判定对象，无芯片或非能量炮时为空。
func accepted_shot(controller: PlayerCentralController, rules: CentralRules, weapon: Dictionary) -> CentralFatalShot:
	if controller == null or rules == null or controller.grade("gun") == 0 or String(weapon.get("skill_id", "")) != "energy_cannon": return null
	var id := String(weapon.get("instance_id", ""))
	return null if id.is_empty() else CentralFatalShot.new(controller, rules, id)


## 消耗首次接触资格，再检查开火者和原炮仍然有效，最后抽取独立概率。
## [param shot] 本发判定。[param condition] 当前装备。[param attacker_alive] 开火者是否存活。
## [param remaining_health] 普通命中后剩余生命。[param ordinary_damage] 实际普通伤害。
## 返回受上限约束的额外伤害，不在此方法扣血或发奖。
func resolve(shot: CentralFatalShot, condition: EquipmentConditionLoadout, attacker_alive: bool, remaining_health: int, ordinary_damage: int) -> int:
	if shot == null or not shot.claim_contact(): return 0
	if not attacker_alive or remaining_health <= 0 or ordinary_damage <= 0 or not condition.has_healthy_cannon(shot.weapon_instance_id): return 0
	return shot.controller.fatal_damage(remaining_health, ordinary_damage, _random.randf(), shot.rules)
