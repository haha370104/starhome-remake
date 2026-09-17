class_name AuthoritativeGeneratorModule
extends RefCounted

var _activations: Dictionary[String, GeneratorActivation] = {}
var _random := RandomNumberGenerator.new()


## 建立装置独立随机序列，不扰动现有基础伤害和掉落随机结果。
## [param random_seed] 地图服务器种子。
func reset(random_seed: int) -> void:
	_activations.clear()
	_random.seed = random_seed


## 对已确认非致死的能量炮命中判定两件发生器，只接受开火时已装且命中时仍在的实例。
## [param actor_id] 权威攻击者。
## [param fired_instances] 开火时记录的发生器身份。
## [param condition] 同一玩家的运行期装配与弹仓。
## [param state] 同一玩家的战车资源。
## [param monster] 已命中的存活怪物。
## [param tick] 当前时钟。
## [param simulation_hz] 模拟频率。
func on_hit(actor_id: String, fired_instances: PackedStringArray, condition: EquipmentConditionLoadout, state: VehicleCombatState, monster: MonsterLifecycle, tick: int, simulation_hz: int) -> void:
	if not _activations.has(actor_id): _activations[actor_id] = GeneratorActivation.new()
	for item: VehicleEquipment in condition.generators():
		if item.instance_id in fired_instances and _activations[actor_id].try_activate(item, state, tick, simulation_hz, _random.randf()):
			monster.generator_afflictions.apply(item.generator_profile, actor_id, item.instance_id, tick, simulation_hz)


## 为开火和换装建立轻量身份快照，既不复制弹量也不保存控件引用。
## [param condition] 当前权威装备条件。
## 返回可提供效果的发生器实例身份。
static func instances(condition: EquipmentConditionLoadout) -> PackedStringArray:
	var result := PackedStringArray()
	for item: VehicleEquipment in condition.generators(): result.append(item.instance_id)
	return result


## 换装时清理离开实例造成的状态，保留仍装配发生器的冷却与持续效果。
## [param actor_id] 刷新装配或离开的玩家。
## [param retained] 仍有效的来源实例；死亡、切图、断开传空。
## [param monsters] 当前地图拥有的领域怪物集合。
func retain_sources(actor_id: String, retained: PackedStringArray, monsters: Dictionary) -> void:
	if _activations.has(actor_id):
		_activations[actor_id].retain(retained)
		if retained.is_empty(): _activations.erase(actor_id)
	for monster: MonsterLifecycle in monsters.values():
		monster.generator_afflictions.remove_source(actor_id, retained)
