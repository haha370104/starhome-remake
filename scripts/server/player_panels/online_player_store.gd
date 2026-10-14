class_name OnlinePlayerStore
extends RefCounted

var _mapper: PlayerStateMapper
var _players: Dictionary = {}
var _facts: Dictionary = {}
var _warehouses: Dictionary = {}


## 配置在线聚合的唯一恢复边界。
## [param mapper] 共享目录与规则的映射器。
func _init(mapper: PlayerStateMapper) -> void:
	_mapper = mapper


## 将权威记录同步到稳定 Player 身份，未变化物品及装配不重复实例化。
## [param state] 权威当前状态；包含同 revision 的经验与耐久变化。
## 返回仅供投影和显式隔离事务读取的在线聚合，禁止调用方直接写入。
func observe(state: PlayerStateRecord) -> DomainResult:
	if state == null: return DomainResult.failure(&"player.missing", "在线角色记录缺失")
	var id := state.character_id
	var raw := state.to_dictionary(false)
	var previous: Player = _players.get(id)
	if previous != null and _facts[id] == raw and _warehouses.get(id) == state.warehouse:
		return DomainResult.ok(previous)
	var restored := _mapper.restore_reusing(state, previous, _facts.get(id, {}))
	if not restored.is_ok: return restored
	if previous == null:
		previous = restored.value
		_players[id] = previous
	else: PlayerTransaction.adopt(previous, restored.value)
	_facts[id] = raw
	_warehouses[id] = state.warehouse
	return DomainResult.ok(previous)


## 释放不再在线的角色，避免长时间保留背包与装备实例。
## [param character_id] 离线或退出的角色。
func forget(character_id: String) -> void:
	_players.erase(character_id)
	_facts.erase(character_id)
	_warehouses.erase(character_id)
