extends SceneTree

const CHILD_FLAG := "--warning-scan-child"
const ENTRY_POINTS := ["res://scripts/main_hall.gd", "res://scripts/server/authoritative_server.gd"]
var _warnings: Array[Dictionary] = []
var _errors: Array[Dictionary] = []


## 在子进程解析正式入口，在父进程接收与编辑器相同的远程调试警告。
func _initialize() -> void:
	if CHILD_FLAG in OS.get_cmdline_user_args():
		call_deferred("_scan_child")
	else:
		call_deferred("_capture")


## 只解析脚本，不启动游戏场景、服务器连接或玩家存档。
func _scan_child() -> void:
	var valid := true
	for path: String in ENTRY_POINTS:
		var parsed := load(path) as GDScript
		valid = parsed != null and parsed.can_instantiate() and valid
	var marker_path := _argument_value("--scan-marker=")
	var marker := FileAccess.open(marker_path, FileAccess.WRITE)
	if marker == null:
		quit(2)
		return
	marker.store_string(JSON.stringify({"loaded": valid, "entries": ENTRY_POINTS}))
	marker.close()
	# 给远程调试器留出发送缓冲的时间，避免最后一批警告被进程退出截断。
	await create_timer(0.3).timeout
	quit(0 if valid else 1)


## 监听仅本机端口，启动隔离扫描子进程，保存文件/行号/警告代码并以非零状态阻止回归。
func _capture() -> void:
	var output_dir := ProjectSettings.globalize_path("res://.godot/warning-scan-%d" % OS.get_process_id())
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		push_error("Cannot create warning report directory")
		quit(2)
		return
	var listener := TCPServer.new()
	var port := 0
	for offset in range(32):
		var candidate := 49152 + posmod(OS.get_process_id() + offset, 10000)
		if listener.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			break
	if port == 0:
		push_error("No local debugger port available")
		quit(2)
		return
	var marker_path := output_dir.path_join("child_result.json")
	var child := OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--remote-debug", "tcp://127.0.0.1:%d" % port,
		"--log-file", output_dir.path_join("child.log"),
		"--script", "res://tools/check_gdscript_warnings.gd", "--", CHILD_FLAG,
		"--scan-marker=%s" % marker_path,
	]), false)
	if child <= 0:
		push_error("Could not launch GDScript warning scan")
		quit(2)
		return
	var peer := PacketPeerStream.new()
	var connection: StreamPeerTCP = null
	var deadline := Time.get_ticks_msec() + 20000
	var received_packet := false
	while Time.get_ticks_msec() < deadline:
		if connection == null and listener.is_connection_available():
			connection = listener.take_connection()
			peer.stream_peer = connection
		if connection != null:
			connection.poll()
			while peer.get_available_packet_count() > 0:
				received_packet = true
				_collect_packet(peer.get_var())
		if not OS.is_process_running(child):
			break
		await process_frame
	var timed_out := OS.is_process_running(child)
	if timed_out:
		OS.kill(child)
	listener.stop()
	var child_loaded := false
	if FileAccess.file_exists(marker_path):
		var marker: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker_path))
		child_loaded = marker is Dictionary and bool(marker.get("loaded", false))
	var report := {
		"engine_version": Engine.get_version_info()["string"], "entry_points": ENTRY_POINTS,
		"child_loaded": child_loaded, "received_packet": received_packet, "timed_out": timed_out,
		"warnings": _warnings, "errors": _errors,
	}
	var report_path := output_dir.path_join("warnings.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		push_error("Cannot save warning report")
		quit(2)
		return
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	for issue: Dictionary in _warnings + _errors:
		print("%s:%d [%s] %s" % [issue["file"], issue["line"], issue["code"], issue["message"]])
	var passed := child_loaded and received_packet and not timed_out and _warnings.is_empty() and _errors.is_empty()
	print("GDSCRIPT_WARNINGS_%s warnings=%d errors=%d report=%s" % [
		"OK" if passed else "FAILED", _warnings.size(), _errors.size(), report_path])
	quit(0 if passed else 1)


## 解码 Godot 调试协议的错误包；保留全部警告，只忽略沙箱中已知的系统证书读取错误。
## [param packet] 本机扫描子进程发来的 Variant 消息。
func _collect_packet(packet: Variant) -> void:
	if not packet is Array or packet.size() < 3 or packet[0] != "error":
		return
	var fields: Variant = packet[2]
	if not fields is Array or fields.size() < 10:
		return
	var file := String(fields[4])
	var message := String(fields[8])
	if file == "platform/windows/os_windows.cpp" and message == "Failed to read the root certificate store.":
		return
	var issue := {"file": file, "line": int(fields[6]), "code": String(fields[7]), "message": message}
	if bool(fields[9]):
		_warnings.append(issue)
	else:
		_errors.append(issue)


## 获取子进程私有输出参数，不接受额外扫描路径。
## [param prefix] 固定的参数前缀。
## 返回对应参数值，缺失时为空字符串。
func _argument_value(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""
