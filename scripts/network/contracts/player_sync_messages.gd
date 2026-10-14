class_name PlayerSyncMessages
extends RefCounted


## 只在已知玩家消息槽转换投影，不递归扫描世界快照或任意业务载荷。
## [param message] 原有可靠消息。[param converter] 完整投影或增量信封的转换器。
## 返回保留原业务外壳的新消息或转换失败。
static func transform(message: Dictionary, converter: Callable) -> DomainResult:
	if message.get("player_change") is Dictionary or (message.get("character") is Dictionary \
			and message.get("inventory") is Dictionary and message.get("vehicle") is Dictionary):
		return converter.call(message)
	var result := message.duplicate(false)
	for key: String in ["result", "value", "panel_bundle"]:
		if not message.get(key) is Dictionary: continue
		var child := transform(message[key], converter)
		if not child.is_ok: return child
		result[key] = child.value
	return DomainResult.ok(result)
