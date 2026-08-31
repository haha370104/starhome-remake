extends SceneTree

const ConfigScript := preload("res://scripts/server/server_config.gd")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")

var failures: PackedStringArray = []
var assertions := 0


## 执行本测试脚本的全部验证并汇总结果。
func _initialize() -> void:
	var config = ConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = false
	var server = ServerScript.new()
	var initialized := server.initialize(config)
	_expect(initialized.ok, "权威服务器应完成初始化：%s" % initialized)
	if not initialized.ok:
		_finish()
		return
	var initial_count: int = server.map_registry.all_instances().size()
	_expect(initial_count == 0, "无玩家启动时不能预建任何地图实例")
	_expect(server.map_instance == null, "默认出生地图也应等首个玩家加入后才加载")
	server.advance_simulation(1.0, 0)
	_expect(server.map_registry.all_instances().is_empty(), "空服务器推进时间不能生成地图或怪物")
	_expect(
		server.map_registry.instance_by_map_id("glory_nft_bl_2armshop1") == null,
		"全量地图不应在启动时预建 A* 实例",
	)
	var loaded := server.ensure_runtime_map("glory_nft_bl_2armshop1")
	_expect(loaded.ok, "首次进入兵工厂应惰性加载：%s" % loaded)
	if loaded.ok:
		_expect(loaded.value.definition.display_name == "兵工厂", "惰性地图中文名不匹配")
		_expect(loaded.value.navigation != null, "惰性地图必须构建权威导航")
		_expect(loaded.value.combat_module != null, "惰性地图必须配置权威战斗模块")
		_expect(loaded.value.mining_module != null, "惰性地图必须配置权威采矿模块")
	_expect(server.map_registry.all_instances().size() == initial_count + 1, "首次加载只应新增一个实例")
	var repeated := server.ensure_runtime_map("glory_nft_bl_2armshop1")
	_expect(repeated.ok and repeated.value == loaded.value, "重复进入应复用同一权威实例")
	_expect(server.map_registry.all_instances().size() == initial_count + 1, "重复进入不得重复登记")
	var rejected := server.ensure_runtime_map("client_supplied_missing_map")
	_expect(not rejected.ok and rejected.code == &"runtime_map_unknown", "未知地图 ID 必须被受控索引拒绝")
	_finish()


## 汇总测试断言并以对应退出码结束测试。
func _finish() -> void:
	if failures.is_empty():
		print("LAZY_GLORY_MAP_LOADING_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 记录一项测试断言及其失败信息。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
