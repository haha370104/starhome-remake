extends SceneTree

const LoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const CatalogScript := preload("res://scripts/maps/map_catalog.gd")
const NavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")
const TransitionMarkerCatalogScript := preload(
	"res://scripts/client/world/map_transition_marker_catalog.gd"
)
const DIRECTORY_PATH := "res://data/maps/map_directory.json"
const WORLD_GRAPH_PATH := "res://data/maps/world_graph_seed.json"

const EXPECTED_DEFINITIONS := {
	"yian_harbor_hall_floor_1": "res://data/maps/yian_harbor_hall_floor_1.json",
	"yian_harbor_city": "res://data/maps/yian_harbor_city.json",
	"d04_field_zone": "res://data/maps/d04_field_zone.json",
	"g08_field_zone": "res://data/maps/g08_field_zone.json",
}
const EXPECTED_NAVIGATION_HASHES := {
	"yian_harbor_hall_floor_1": "d68ad7bc872fb1d907ca6ecb2410cc782e631f846d03a9b4b3b0dacc5b45a327",
	"yian_harbor_city": "46bfb65fc3a6c5faef835ec35602139bec96d3a29469bfe313136ca25a5a3fde",
	"d04_field_zone": "6596d9afc3b99553649f5d980de0365dc51a36eacb50a2e07fc0075fa612f65b",
	"g08_field_zone": "df15d24a1bb74f63385d10d51e2419e3ffa5669810b52dc6b1d1913dc21537dc",
}

var failures: PackedStringArray = []
var assertions := 0


## 验证阶段 2 荣耀版地图目录、真实拓扑、出生点证据和导航文件完整性。
## 设计：网络只交换 map_id；本测试确保 map_id 到本地资源路径的映射只来自受控目录。
func _initialize() -> void:
	var directory := _read_json_object(DIRECTORY_PATH)
	var graph := _read_json_object(WORLD_GRAPH_PATH)
	_test_directory(directory)
	_test_world_graph(graph)
	_test_definitions(directory)
	if failures.is_empty():
		print("GLORY_WORLD_GRAPH_DATA_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 执行 `test_directory` 对应的模块操作。
## [param directory] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _test_directory(directory: Dictionary) -> void:
	_expect(int(directory.get("schema_version", 0)) == 1, "地图目录 schema 版本错误")
	var definitions: Variant = directory.get("definitions", {})
	_expect(definitions is Dictionary, "地图目录 definitions 必须是 object")
	if not definitions is Dictionary:
		return
	_expect(definitions.size() == EXPECTED_DEFINITIONS.size(), "地图目录不得静默增删定义")
	for map_id in EXPECTED_DEFINITIONS:
		_expect(
			String(definitions.get(map_id, "")) == EXPECTED_DEFINITIONS[map_id],
			"地图目录路径不匹配：%s" % map_id,
		)
		_expect(FileAccess.file_exists(EXPECTED_DEFINITIONS[map_id]), "地图定义不存在：%s" % map_id)


## 执行 `test_world_graph` 对应的模块操作。
## [param graph] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _test_world_graph(graph: Dictionary) -> void:
	var slice: Dictionary = graph.get("vertical_slice", {})
	_expect(
		Array(slice.get("route_map_ids", [])) == [
			"yian_harbor_hall_floor_1", "yian_harbor_city", "d04_field_zone",
		],
		"阶段 2 纵切必须保留 RoomSvr1→City1Svr→D04，不得伪造大厅直达野外",
	)
	_expect(
		String(slice.get("topology_evidence", "")).contains("no direct field edge"),
		"真实拓扑限制没有写入结构化证据",
	)
	var gaps: Array = graph.get("known_gaps", [])
	_expect(gaps.size() >= 5, "缺失落点、场景素材和延后出口必须结构化记录")


## 执行 `test_definitions` 对应的模块操作。
## [param directory] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _test_definitions(directory: Dictionary) -> void:
	var catalog = CatalogScript.new()
	var marker_catalog = TransitionMarkerCatalogScript.new()
	_expect(marker_catalog.load_default() == OK, "八方向传送点公共目录必须可加载")
	var definitions_by_id := {}
	for map_id in EXPECTED_DEFINITIONS:
		var loader = LoaderScript.new()
		var definition = loader.load_file(EXPECTED_DEFINITIONS[map_id])
		_expect(definition != null, "地图定义加载失败 %s：%s" % [map_id, loader.errors])
		if definition == null:
			continue
		definitions_by_id[map_id] = definition
		_expect(String(definition.map_id) == map_id, "目录 key 与定义 map_id 不一致：%s" % map_id)
		_expect(catalog.add_map(definition), "地图目录加入失败：%s" % map_id)
		_test_navigation(definition)
		_test_spawns(definition)
		_test_transition_presentations(definition, marker_catalog)

	_expect(catalog.validate_links(), "内部地图边必须全部解析：%s" % catalog.errors)
	if definitions_by_id.size() != EXPECTED_DEFINITIONS.size():
		return
	var hall = definitions_by_id["yian_harbor_hall_floor_1"]
	_expect(hall.transitions.size() == 1, "RoomSvr1 应只有一个有效出口")
	_expect(
		hall.transition_by_id(&"exit_to_city").destination_map_id == &"yian_harbor_city",
		"大厅唯一出口必须指向 City1Svr 业务定义",
	)
	_expect(
		String(hall.transition_by_id(&"exit_to_city").presentation.get("orientation", "")) == "north_west",
		"大厅出口必须忠实采用源 as4 的屏幕左上方向",
	)
	var city = definitions_by_id["yian_harbor_city"]
	_expect(city.transitions.size() == 5, "City1Svr 本纵切应提升大厅边和四条 D04 边")
	for entry_number in range(5):
		_expect(city.spawn_for_entry(entry_number) != null, "City1Svr 缺少入口 %d 出生点" % entry_number)
	var city_hall_transition: MapTransition = city.transition_by_id(&"enter_base_hall_floor_1")
	_expect(
		String(city_hall_transition.presentation.get("orientation", "")) == "north_east",
		"城区基地入口必须忠实采用源 as2 的屏幕右上方向",
	)
	_expect(int(city_hall_transition.source_audit.get("source_marker_style", 0)) == 2, "城区基地入口必须保留源 as2 审计")
	var d04 = definitions_by_id["d04_field_zone"]
	_expect(d04.transitions.size() == 12, "D04 的 12 条荣耀版有效出口必须全部保留")
	for transition: MapTransition in d04.transitions:
		_expect(
			String(transition.source_audit.get("source_marker_family", "")) == "field_directional_marker",
			"D04 必须保留源 jt 标记族，不得伪装成城区 as 关联",
		)
	for entry_number in range(1, 5):
		_expect(d04.spawn_for_entry(entry_number) != null, "D04 缺少城市入口 %d 出生点" % entry_number)
	_test_g08_transitions(definitions_by_id["g08_field_zone"])


## 验证每张正式地图只声明传送方向，并能通过公共目录解析为完整动画表现。
## [param definition] 待检查的地图定义。
## [param marker_catalog] 已加载的八方向传送点公共目录。
func _test_transition_presentations(definition, marker_catalog) -> void:
	for transition: MapTransition in definition.transitions:
		if not transition.enabled:
			continue
		var presentation: Dictionary = transition.presentation
		_expect(not presentation.is_empty(), "启用的传送点必须声明公共组件方向：%s/%s" % [definition.map_id, transition.transition_id])
		_expect(String(presentation.get("kind", "")) == "directional_transition", "地图不得直接配置传送动画资源")
		_expect(not presentation.has("resource"), "地图定义不得重复保存共享传送动画路径")
		var resolved: Dictionary = marker_catalog.resolve(
			StringName(String(presentation.get("orientation", ""))),
			transition.source_anchor,
		)
		_expect(not resolved.is_empty(), "传送方向必须能由公共目录解析：%s" % transition.transition_id)
		if resolved.is_empty():
			continue
		_expect(int(resolved.get("frame_count", 0)) in [9, 10], "as1-as8 必须保留完整 9 或 10 帧")
		_expect(int(resolved.get("frame_duration_ms", 0)) == 100, "传送点必须保持 100 毫秒源播放间隔")
		_expect(ResourceLoader.exists(String(resolved.get("resource", ""))), "共享传送动画资源必须可加载")


## 执行 `test_navigation` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _test_navigation(definition) -> void:
	var path: String = String(definition.navigation_data_path)
	_expect(FileAccess.file_exists(path), "导航文件不存在：%s" % path)
	if not FileAccess.file_exists(path):
		return
	_expect(
		FileAccess.get_sha256(path) == EXPECTED_NAVIGATION_HASHES[String(definition.map_id)],
		"导航 SHA-256 与荣耀版提取证据不一致：%s" % definition.map_id,
	)
	var navigation = NavigationScript.new()
	_expect(
		navigation.load_from(path, definition.navigation_grid_size, definition.navigation_cell_size),
		"导航网格无法按 MapDefinition 加载：%s" % definition.map_id,
	)
	_expect(
		navigation.data.size() == definition.navigation_grid_size.x * definition.navigation_grid_size.y,
		"导航字节数与网格尺寸不一致：%s" % definition.map_id,
	)


## 执行 `test_spawns` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _test_spawns(definition) -> void:
	_expect(not definition.spawn_points.is_empty(), "正式地图缺少出生点：%s" % definition.map_id)
	_expect(definition.spawn_by_id(definition.default_spawn_id) != null, "默认出生点无法解析")
	var navigation = NavigationScript.new()
	if not navigation.load_from(
		definition.navigation_data_path,
		definition.navigation_grid_size,
		definition.navigation_cell_size,
	):
		return
	for spawn_point in definition.spawn_points:
		if spawn_point.enabled:
			_expect(
				navigation.is_walkable(spawn_point.position),
				"出生点不在可走格：%s/%s" % [definition.map_id, spawn_point.spawn_id],
			)


## 执行 `test_g08_transitions` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _test_g08_transitions(definition) -> void:
	_expect(definition.transitions.size() == 5, "G08 必须保留五条已确认出口")
	var actual_codes: PackedStringArray = []
	for transition in definition.transitions:
		actual_codes.append(transition.destination_legacy_code)
		_expect(transition.external_target, "G08 未提升的目标必须显式标记 external")
		_expect(
			String(transition.source_audit.get("source_marker_family", "")) == "house_directional_marker",
			"G08 必须保留源 as 标记族",
		)
	actual_codes.sort()
	_expect(actual_codes == PackedStringArray(["f07", "f08", "g07", "h07", "h08"]), "G08 目的地集合错误")


## 执行 `read_json_object` 对应的模块操作。
## [param path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _read_json_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_expect(false, "JSON 文件不存在：%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_expect(false, "JSON 根节点不是 object：%s" % path)
		return {}
	return parsed


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
