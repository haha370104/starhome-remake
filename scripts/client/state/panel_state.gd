class_name PanelState
extends RefCounted

var _bundle: Dictionary = {}


## 保存客户端当前可展示的玩家面板投影；不持有可变领域对象。
## [param bundle] 已通过 CurrentPlayer 校验的完整面板快照。
func replace_bundle(bundle: Dictionary) -> void:
	_bundle = bundle.duplicate(true)


## 清空旧同步世代，避免窗口继续读取过期面板数据。
func clear() -> void:
	_bundle.clear()


## 判断人物、背包和战车三个核心领域是否均已同步。
func is_ready() -> bool:
	return _bundle.get("character") is Dictionary \
		and _bundle.get("inventory") is Dictionary \
		and _bundle.get("vehicle") is Dictionary


## 返回完整投影副本；窗口不得修改会话内部状态。
func snapshot_bundle() -> Dictionary:
	return _bundle.duplicate(true)


## 返回指定领域的独立快照；不存在时返回空字典。
## [param domain] character、inventory、vehicle 等投影键。
func slice(domain: String) -> Dictionary:
	var value: Variant = _bundle.get(domain, {})
	return value.duplicate(true) if value is Dictionary else {}


## 读取事务或领域 revision，供窗口命令和局部刷新判断版本。
## [param domain] transaction、character、inventory 或 vehicle。
func domain_revision(domain: String) -> int:
	if domain == "transaction": return int(_bundle.get("transaction_revision", -1))
	var value: Variant = _bundle.get(domain, {})
	if not value is Dictionary: return -1
	return int(value.get("revision", -1))
