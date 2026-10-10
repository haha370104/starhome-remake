extends SceneTree

const ChatService := preload("res://scripts/server/social/authoritative_chat_service.gd")
const History := preload("res://scripts/server/social/private_chat_history.gd")

var checks := 0
var failures: Array[String] = []
var names := {"human": "karei", "llm": "Riko", "third": "旁观者"}
var sessions := SessionService.new()
var delivered: Array[Dictionary] = []
var directory := "user://private-chat-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func _initialize() -> void:
	call_deferred("_run")


func _service(path: String) -> AuthoritativeChatService:
	var service := ChatService.new()
	var configured := service.configure(Callable(sessions, "session_for_entity"),
		func(entity_id: String) -> String: return "city" if entity_id == "human" else "wilderness",
		func(entity_id: String) -> String: return String(names.get(entity_id, entity_id)),
		func(_map_id: String) -> Array[String]: return [],
		func(entity_id: String) -> bool: return sessions.session_for_entity(entity_id) != null,
		func(entity_id: String, message: Dictionary) -> void: delivered.append({"recipient": entity_id, "message": message}),
		Callable(), path)
	_expect(configured.is_ok, "聊天服务初始化")
	return service


func _query(service: AuthoritativeChatService, actor_id: String, target_id: Variant, cursor: Variant = null) -> DomainResult:
	return service.execute(actor_id, {"type": "query_private_chat_history", "target_entity_id": target_id, "cursor": cursor})


func _run() -> void:
	sessions.create(1, "human", 0)
	sessions.create_llm("llm", 0)
	sessions.create(3, "third", 0)
	var service := _service(directory)
	_expect(_query(service, "human", "llm").value.private_chat_history.messages.is_empty(), "首次私聊没有历史")
	var first_id := ""
	for index in 501:
		var actor_id := "human" if index % 2 == 0 else "llm"
		service.remove_expired_entity(actor_id)
		var sent := service.execute(actor_id, {"type": "chat_send", "channel": "private", "target_entity_id": "llm" if actor_id == "human" else "human", "message": "相同内容"})
		if not sent.is_ok:
			_expect(false, "跨图双向私聊发送：" + sent.error_message)
			break
		if index == 0: first_id = sent.value.event.message_id
	_expect(delivered.size() == 1002, "每条成功消息只实时送达双方一次")
	var public_event: Dictionary = ObservationPolicy.public_value(delivered[0].message.result.value.event, "human")
	_expect(not public_event.has("message_id") and not public_event.has("sequence"), "实时事件也不向模型暴露内部消息标识或序号")
	_expect(service.history.close().is_ok, "正常退出排空后台写入")
	_expect(DirAccess.get_files_at(ProjectSettings.globalize_path(directory)).size() == 1, "双方共用一份会话文件")
	service = _service(directory)
	var page: Dictionary = _query(service, "human", "llm").value.private_chat_history
	_expect(page.messages.size() == 50 and page.messages[0].sequence == 452 and page.messages.back().sequence == 501 and page.oldest_sequence == 2, "重启恢复最近50条并返回有效历史边界")
	_expect(_query(service, "llm", "human").value.private_chat_history.messages == page.messages, "双方查询同一历史")
	var all: Array = page.messages.duplicate()
	while page.next_cursor != null:
		page = _query(service, "human", "llm", page.next_cursor).value.private_chat_history
		all.append_array(page.messages)
	_expect(all.size() == 500 and all.back().sequence == 51 and all[450].sequence == 2, "分页完整读取保留的500条，删除最早一条")
	var identifiers := {}
	for row: Dictionary in all: identifiers[row.message_id] = true
	_expect(identifiers.size() == 500 and not identifiers.has(first_id), "同文消息不去重且消息标识持久唯一")
	_expect(_query(service, "human", "llm", first_id).error_code == &"chat.cursor_expired", "被截断的游标明确失效")
	_expect(_query(service, "third", "llm").value.private_chat_history.messages.is_empty()
		and _query(service, "third", "llm", all[0].message_id).error_code == &"chat.cursor_expired", "第三方不能借对象或游标读取别人的会话")
	_expect(not service.execute("third", {"type": "query_private_chat_history", "target_entity_id": "llm", "cursor": null, "actor_id": "human"}).is_ok, "拒绝伪造查询者身份")
	names.llm = "改名后的 Riko"
	sessions.close_entity("llm")
	_expect(_query(service, "human", "llm").value.private_chat_history.player_name == names.llm, "改名及对方下线不影响历史")
	_expect(service.execute("human", {"type": "chat_send", "channel": "private", "target_entity_id": "llm", "message": "离线消息"}).error_code == &"chat.target_unavailable", "不增加离线投递")
	var count := delivered.size()
	var server := AuthoritativeServer.new()
	server.chat_service = service
	var result: DomainResult = server._inspect_llm_service("human", {"player_name": names.llm, "cursor": null}, "inspect_private_chat")
	_expect(result.is_ok and result.value.messages.size() == 50, "LLM服务查询读取自己的真实历史")
	var serialized := JSON.stringify(result.value)
	_expect(not "entity_id" in serialized and not "message_id" in serialized and not "sequence" in serialized and not directory in serialized, "LLM结果不泄露内部身份、序号或路径")
	_expect(service.inspect_private_chat("third", names.llm, null).error_code == &"chat.history_missing", "LLM查询也不能越权")
	_expect(delivered.size() == count, "历史查询不广播、不重放为新消息")
	names.third = names.llm
	sessions.create_llm("llm", 0)
	service.remove_expired_entity("human")
	service.execute("human", {"type": "chat_send", "channel": "private", "target_entity_id": "third", "message": "另一段会话"})
	_expect(service.inspect_private_chat("human", names.llm, null).error_code == &"chat.ambiguous_name", "同名会话拒绝猜测对象")
	_expect(service.history.close().is_ok, "最后一条消息正常落盘")
	server.free()
	_test_write_retry()
	_test_recovery()
	var memory := _service("")
	memory.remove_expired_entity("human")
	_expect(memory.execute("human", {"type": "chat_send", "channel": "private", "target_entity_id": "llm", "message": "仅内存"}).is_ok
		and _query(memory, "human", "llm").value.private_chat_history.messages.size() == 1, "关闭持久化仍保留本次会话")
	for file_name: String in DirAccess.get_files_at(ProjectSettings.globalize_path(directory)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory).path_join(file_name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	for failure: String in failures: push_error(failure)
	print("PRIVATE_CHAT_HISTORY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_write_retry() -> void:
	var blocker_path := ProjectSettings.globalize_path(directory).path_join("blocker")
	var blocker := FileAccess.open(blocker_path, FileAccess.WRITE)
	blocker.close()
	var history := History.new()
	history.configure(blocker_path + "/history")
	var event := {"sender_entity_id": "human", "target_entity_id": "llm", "sender_name": "karei", "target_name": "Riko", "message": "待重试", "sent_at_unix_msec": 1791558000000}
	_expect(history.append(event).is_ok, "后台保存入队不阻塞聊天")
	history._writer.flush()
	_expect(history._writer.failures().size() == 1 and history.page("human", "llm").value.messages.size() == 1, "真实写盘失败保留未保存消息")
	DirAccess.remove_absolute(blocker_path)
	_expect(history.append(event).is_ok and history.close().is_ok, "后续消息重试失败会话，退出完成落盘")
	var restored := History.new()
	_expect(restored.configure(blocker_path + "/history").is_ok and restored.page("human", "llm").value.messages.size() == 2, "恢复两条同文消息，旧重试不能覆盖新消息")
	restored.close()
	for file_name: String in DirAccess.get_files_at(blocker_path + "/history"):
		DirAccess.remove_absolute((blocker_path + "/history").path_join(file_name))
	DirAccess.remove_absolute(blocker_path + "/history")
	DirAccess.remove_absolute(blocker_path)


func _test_recovery() -> void:
	var path := ProjectSettings.globalize_path(directory).path_join(DirAccess.get_files_at(ProjectSettings.globalize_path(directory))[0])
	var original := FileAccess.get_file_as_string(path)
	var backup := FileAccess.open(path + ".bak", FileAccess.WRITE)
	backup.store_string(original)
	backup.close()
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("invalid")
	broken.close()
	var restored := History.new()
	_expect(restored.configure(directory).is_ok and not restored._conversations.is_empty(), "异常主档从有效备份恢复")
	_expect(restored.close().is_ok, "恢复后回收线程")
	DirAccess.remove_absolute(path + ".bak")
	var corrupt := History.new()
	corrupt.configure(directory)
	_expect(corrupt._errors.size() == 1 and FileAccess.get_file_as_string(path) == "invalid", "损坏且无备份时保留原档并明确标记错误")
	corrupt.close()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
