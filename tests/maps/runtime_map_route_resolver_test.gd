extends SceneTree

const BootstrapScript := preload("res://scripts/content/runtime_content_bootstrap.gd")
const LoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const ResolverScript := preload("res://scripts/maps/runtime_map_route_resolver.gd")
const DIRECTORY_PATH := "res://data/maps/glory_map_directory_v1.json"

var failures: PackedStringArray = []
var assertions := 0


## 验证 D04 的旧 external 边能通过荣耀版全量索引解析到已打包的运行地图。
func _initialize() -> void:
	var mounted: Dictionary = BootstrapScript.mount_default()
	_expect(bool(mounted.get("ok", false)), "荣耀版内容包必须可挂载")
	var directory: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY_PATH))
	_expect(directory is Dictionary, "全量地图目录必须可读取")
	if not directory is Dictionary:
		_finish()
		return
	var resolver = ResolverScript.new()
	_expect(resolver.configure(directory["definitions"]), "; ".join(resolver.errors))
	_expect(
		resolver.size() == (directory["definitions"] as Dictionary).size(),
		"路由解析器必须覆盖受控目录中的全部可运行地图",
	)
	var loader = LoaderScript.new()
	var d04: MapDefinition = loader.load_file("res://data/maps/d04_field_zone.json")
	_expect(d04 != null, "D04 定义必须可读取")
	if d04 == null:
		_finish()
		return
	var expected_targets := {
		&"exit_to_c04_field": &"buli_c04_field_zone",
		&"exit_to_c05_field": &"buli_c05_field_zone",
		&"exit_to_d03_field": &"buli_d03_field_zone",
		&"exit_to_d05_field": &"buli_d05_field_zone",
		&"exit_to_e03_field": &"glory_nft_bl_e03",
		&"exit_to_e04_field": &"glory_nft_bl_e04",
		&"exit_to_e05_field": &"glory_nft_bl_e05",
	}
	for transition_id: StringName in expected_targets:
		var transition := d04.transition_by_id(transition_id)
		_expect(transition != null, "D04 缺少传送边：%s" % transition_id)
		if transition != null:
			_expect(
				resolver.resolve_target_id(transition, d04.world_id) == expected_targets[transition_id],
				"D04 旧代码目标未解析：%s" % transition_id,
			)
	_finish()


## 汇总断言并以进程退出码报告路由回归结果。
func _finish() -> void:
	if failures.is_empty():
		print("RUNTIME_MAP_ROUTE_RESOLVER_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 记录一条路由回归断言。
## [param condition] 业务约束是否满足。
## [param message] 断言失败时输出的诊断文本。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
