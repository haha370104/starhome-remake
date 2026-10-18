class_name AiPlayerMemory
extends RefCounted

var _directory: String
var _writer: BackgroundFileWriter


## 仅在模块启用后启动低优先级独立记忆写入线程。
## [param directory] 本地记忆目录。
## 返回线程启动是否成功。
func start(directory: String) -> bool:
	_directory = ProjectSettings.globalize_path(directory)
	_writer = BackgroundFileWriter.new()
	return _writer.start() == OK


## 读取有限计划和自身结果，不把旧记忆当成命令直接执行。
## [param actor] 当前独立角色。
func restore(actor: AiPlayerActor) -> void:
	var path := _directory.path_join(actor.key + ".json")
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 65536: return
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not raw is Dictionary or raw.get("actor") != actor.key: return
	if raw.get("memory") is String: actor.memory = raw.memory.left(256)
	if raw.get("history") is Array:
		for row: Variant in raw.history.slice(-20):
			if row is Dictionary and JSON.stringify(row).length() <= 512: actor.history.append(row.duplicate(true))


## 合并异步写入，不保存原始模型响应、凭据或整个游戏快照。
## [param actor] 待保存的有限记忆。
func save(actor: AiPlayerActor) -> void:
	if _writer != null:
		_writer.enqueue_snapshot(_directory.path_join(actor.key + ".json"),
			{"actor": actor.key, "memory": actor.memory.left(256), "history": actor.history.duplicate(true)})


## 退出时排空本模块文件队列；网络请求由提供器单独取消。
## 返回实际文件写入结果。
func close() -> DomainResult:
	if _writer == null: return DomainResult.ok()
	var result := _writer.close()
	_writer = null
	return result
