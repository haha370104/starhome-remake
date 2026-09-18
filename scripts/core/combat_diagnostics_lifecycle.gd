extends Node


## 在场景加载期启动日志线程，避免第一发炮承担线程创建开销。
func _ready() -> void:
	CombatTraceLogger.start()


## 所有游戏场景释放后排空诊断日志，正常退出不遗漏尾部记录。
func _exit_tree() -> void:
	CombatTraceLogger.shutdown()
