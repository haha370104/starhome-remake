class_name ScenePlayerListProjector
extends RefCounted


## 从在线会话与权威角色状态投影当前区域名单，不泄露账号、背包或其他地图玩家。
## [param map_instance_id] 查询者会话所在的权威地图实例，不取客户端参数。
## [param sessions] 服务端会话注册表。
## [param autosave] 权威状态所有者；仅读内存聚合，不产生存档事务。
## 返回用户列表协议，尚未实现的战果和战斗积分明确为 null。
static func build(map_instance_id: String, sessions: SessionRegistry, autosave: RefCounted) -> Dictionary:
	var players: Array[Dictionary] = []
	for session: ServerSession in sessions.all_sessions():
		if not session.has_active_peer() or session.map_instance_id != map_instance_id:
			continue
		var state: PlayerStateRecord = autosave.state_for(session.entity_id)
		if state == null:
			continue
		players.append({"entity_id": session.entity_id, "display_name": state.display_name,
			"sex": state.character_sex, "battle_result": null, "combat_score": null})
	return {"map_instance_id": map_instance_id, "players": players}
