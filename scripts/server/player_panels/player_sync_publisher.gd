class_name PlayerSyncPublisher
extends RefCounted

var _streams: Dictionary = {}


## 按新会话协商能力；没有声明支持的客户端继续获得原完整消息。
## [param peer_id] 传输身份。[param version] 客户端支持的增量格式。
func connect_peer(peer_id: int, version: int) -> void:
	_streams.erase(peer_id)
	if version == PlayerChange.VERSION: _streams[peer_id] = PlayerSyncStream.new()


## 释放断线连接基线，避免复用 peer 编号时串用角色状态。
## [param peer_id] 已离线连接。
func disconnect_peer(peer_id: int) -> void:
	_streams.erase(peer_id)


## 为显式查询强制生成下一份完整投影。
## [param peer_id] 请求重新同步的连接。
func require_full(peer_id: int) -> void:
	if _streams.has(peer_id): (_streams[peer_id] as PlayerSyncStream).require_full()


## 根据连接能力封装可靠玩家消息，其余业务消息原样传送。
## [param peer_id] 已验证连接。[param message] 服务端领域处理后的消息。
## 返回可传输的消息，不改变调用方字典。
func encode(peer_id: int, message: Dictionary) -> Dictionary:
	var stream: PlayerSyncStream = _streams.get(peer_id)
	if stream == null: return message
	var result := PlayerSyncMessages.transform(message, func(bundle: Dictionary) -> DomainResult:
		return DomainResult.ok(stream.encode(bundle)))
	return result.value
