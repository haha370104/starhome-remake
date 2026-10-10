extends SceneTree

const PanelStateScript := preload("res://scripts/client/state/panel_state.gd")
const PlayerPanelSessionScript := preload("res://scripts/client/state/player_panel_session.gd")

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	var state := PanelStateScript.new()
	var source := {"transaction_revision": 8,
		"character": {"revision": 8, "level": 12},
		"inventory": {"revision": 4, "items": []},
		"vehicle": {"revision": 3, "vehicle_id": "vehicle.test"}}
	state.replace_bundle(source)
	_check(state.is_ready(), "完整面板投影可用")
	_check(state.domain_revision("transaction") == 8, "事务 revision 可读取")
	_check(state.domain_revision("inventory") == 4, "背包 revision 可读取")
	var character := state.slice("character")
	character.level = 99
	_check(state.slice("character").level == 12, "领域快照不会反向修改状态")
	source.character.level = 1
	_check(state.slice("character").level == 12, "来源字典后续变化不会污染状态")
	state.clear()
	_check(not state.is_ready() and state.snapshot_bundle().is_empty(), "清空同步世代")

	var commands: Array[Dictionary] = []
	var session := PlayerPanelSessionScript.new(func(command: Dictionary) -> void: commands.append(command))
	session.begin_sync("panel-test")
	session.request_full_sync()
	session.request_full_sync()
	_check(commands.size() == 1 and commands[0].type == "query", "初次同步请求去重")
	session.invalidate_full_sync()
	_check(commands.size() == 2, "显式失效可重新请求完整同步")
	for failure: String in failures: push_error(failure)
	print("PANEL_STATE_OK (%d assertions)" % checks)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
