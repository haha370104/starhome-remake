class_name OnlinePlayerStore
extends RefCounted

var _players: Dictionary[String, Player] = {}


## 登记载入完成的唯一在线聚合；重复登记不会覆盖正在运行的状态。
## [param player] 从存档恢复的玩家。
## 返回实际在线对象。
func register(player: Player) -> Player:
	if not _players.has(player.entity_id): _players[player.entity_id] = player
	return _players[player.entity_id]


## 读取当前在线对象；调用方只能经领域用例和同步事务改变状态。
## [param identity] 权威角色身份。
## 返回在线玩家，不存在时为空。
func player_for(identity: String) -> Player:
	return _players.get(identity)


## 提交同版本候选或已经原子完成的领域操作；不生成持久化记录。
## [param identity] 权威角色身份。[param candidate] 预检成功的候选。
## 返回原位更新后的在线玩家，旧候选被拒绝。
func commit(identity: String, candidate: Player) -> DomainResult:
	var current := player_for(identity)
	if current == null or candidate == null or candidate.entity_id != identity:
		return DomainResult.failure(&"player.missing", "online player is unavailable")
	if candidate.revision != current.revision:
		return DomainResult.failure(&"player.stale", "player changed before transaction commit")
	var revision := current.revision + 1
	if candidate != current: PlayerTransaction.apply(current, candidate)
	current.revision = revision
	return DomainResult.ok(current)


## 预检并一次性提交多个互不相同的玩家候选；用于双边交易等跨聚合事务。
## 任何角色版本不匹配时都不修改其中任一角色。
func commit_many(candidates: Dictionary) -> DomainResult:
	if candidates.is_empty():
		return DomainResult.failure(&"player.empty_transaction", "multi-player transaction is empty")
	for identity: String in candidates:
		var current: Player = player_for(identity)
		var candidate: Player = candidates[identity]
		if current == null or candidate == null or candidate.entity_id != identity \
			or candidate.revision != current.revision:
			return DomainResult.failure(&"player.stale", "a player changed before the multi-player commit")
	var committed: Dictionary = {}
	for identity: String in candidates:
		var current: Player = player_for(identity)
		var candidate: Player = candidates[identity]
		if candidate != current:
			PlayerTransaction.apply(current, candidate)
		current.revision += 1
		committed[identity] = current
	return DomainResult.ok(committed)


## 在存档完成或会话释放后移除在线状态。
## [param identity] 已结束的角色身份。
func remove(identity: String) -> void:
	_players.erase(identity)


## 提供保存时的角色列表副本。
## 返回当前在线角色身份。
func identities() -> Array[String]:
	return _players.keys()
