extends SceneTree

var checks := 0
var failures: Array[String] = []
var received: Array[Dictionary] = []
var response_count := 0
var last_result: DomainResult
var listener := TCPServer.new()
var connection: StreamPeerTCP
var request_bytes := PackedByteArray()


## 用本机模拟HTTP验证真实提供器，不请求外部模型或读取现有密钥。
func _initialize() -> void:
	call_deferred("_run")


## 验证真实异步传输、请求协议、失败和关闭时取消。
func _run() -> void:
	var port := 32200 + int(OS.get_process_id() % 10000)
	_check(listener.listen(port, "127.0.0.1") == OK, "启动本机模拟接口")
	var settings := AiPlayerSettings.new()
	settings.endpoint = "http://127.0.0.1:%d/responses" % port
	settings.model = "local-test-model"
	settings.timeout_seconds = 1
	settings.api_key_env = "STARHOME_AI_TEST_ONLY_KEY"
	OS.set_environment(settings.api_key_env, "local-test-value")
	var provider := AiResponsesProvider.new()
	provider.configure(settings)
	root.add_child(provider)
	provider.completed.connect(func(_id: int, result: DomainResult) -> void:
		response_count += 1
		last_result = result)
	provider.decide(1, {"map_id": "test"}, {"goal": "等待"})
	_check(await _receive(), "HTTP请求经后台传输到达本机")
	if not received.is_empty():
		var body: Dictionary = received.back()
		_check(body.store == false and body.parallel_tool_calls == false, "禁用远端存储及多行动")
		_check(body.tools.size() == 1 and body.tools[0].strict == true, "严格函数工具")
		_check(body.max_output_tokens == settings.max_output_tokens, "令牌上限")
		_check(not JSON.stringify(body).contains("local-test-value"), "密钥不进入模型上下文")
	_respond(200, {"status": "completed", "output": [{"type": "function_call", "name": "choose_action", "arguments": '{"kind":"wait"}'}]})
	await _wait_response(1)
	_check(last_result != null and last_result.is_ok and last_result.value.kind == "wait", "解析实际HTTP函数调用")
	provider.decide(2, {}, {})
	_check(await _receive(), "第二次请求")
	_respond(429, {"error": "should-not-leak"})
	await _wait_response(2)
	_check(last_result != null and not last_result.is_ok and not last_result.error_message.contains("should-not-leak"), "远端错误正文不泄漏")
	provider.decide(3, {}, {})
	_check(await _receive(), "超时请求到达")
	await _wait_response(3)
	_check(response_count == 3 and not last_result.is_ok, "异步超时释放请求")
	if connection != null: connection.disconnect_from_host()
	provider.decide(4, {}, {})
	_check(await _receive(), "取消请求到达")
	provider.cancel()
	_respond(200, {"output": []})
	await create_timer(0.1).timeout
	_check(response_count == 3, "取消后不发布旧结果")
	provider.queue_free()
	listener.stop()
	OS.unset_environment(settings.api_key_env)
	await process_frame
	print("AI HTTP: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 轮询本机测试连接并收齐有长度声明的请求，期间持续让出帧。
## 返回是否在三秒内收到完整请求。
func _receive() -> bool:
	connection = null
	request_bytes.clear()
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if connection == null and listener.is_connection_available(): connection = listener.take_connection()
		if connection != null:
			connection.poll()
			if connection.get_available_bytes() > 0:
				request_bytes.append_array(connection.get_data(connection.get_available_bytes())[1])
			var text := request_bytes.get_string_from_utf8()
			var boundary := text.find("\r\n\r\n")
			if boundary >= 0:
				var length := 0
				for header: String in text.left(boundary).split("\r\n"):
					if header.to_lower().begins_with("content-length:"): length = int(header.split(":")[1])
				var payload := request_bytes.slice(boundary + 4)
				if payload.size() >= length:
					var parsed: Variant = JSON.parse_string(payload.get_string_from_utf8())
					if parsed is Dictionary: received.append(parsed)
					return parsed is Dictionary
		await process_frame
	return false


## 向本机请求写入固定响应，不连接任何外部地址。
## [param status] HTTP状态。[param document] 测试响应。
func _respond(status: int, document: Dictionary) -> void:
	if connection == null: return
	var bytes := JSON.stringify(document).to_utf8_buffer()
	var headers := "HTTP/1.1 %d Test\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, bytes.size()]
	connection.put_data(headers.to_utf8_buffer() + bytes)


## 有界等待真实HTTP完成信号。
## [param count] 期望累计完成数。
func _wait_response(count: int) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while response_count < count and Time.get_ticks_msec() < deadline: await process_frame


## 汇总真实HTTP传输断言。
## [param condition] 实际条件。[param message] 预期说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
