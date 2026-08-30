extends SceneTree

const BootstrapScript := preload("res://scripts/content/runtime_content_bootstrap.gd")
const CatalogScript := preload("res://scripts/maps/map_catalog.gd")
const LandingResolverScript := preload("res://scripts/maps/map_transition_landing_resolver.gd")
const NavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")
const DIRECTORY_PATH := "res://data/maps/glory_map_directory_v1.json"

var failures: PackedStringArray = []
var assertions := 0
var reciprocal_landings := 0
var wrapped_landings := 0
var fallback_landings := 0
var corrected_landings := 0
var navigation_by_map_id: Dictionary = {}


## 审计全部荣耀版内部地图边，确保连续落点存在且位于目标地图可走区域。
func _initialize() -> void:
	var mounted: Dictionary = BootstrapScript.mount_default()
	_expect(bool(mounted.get("ok", false)), "荣耀版地图内容包必须可挂载")
	var directory: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY_PATH))
	_expect(directory is Dictionary, "荣耀版全量地图目录必须可读取")
	if not directory is Dictionary:
		_finish()
		return
	var paths := PackedStringArray()
	for path_value: Variant in (directory.get("definitions", {}) as Dictionary).values():
		paths.append(String(path_value))
	var catalog = CatalogScript.new()
	_expect(catalog.add_files(paths), "荣耀版地图定义必须全部有效：%s" % "; ".join(catalog.errors))
	_expect(catalog.validate_links(), "荣耀版内部地图边必须闭合：%s" % "; ".join(catalog.errors))
	for source: MapDefinition in catalog.all_maps():
		for transition: MapTransition in source.enabled_transitions():
			if transition.kind == MapTransition.Kind.CLIENT_POINT \
					and transition.has_destination_landing_point:
				continue
			var destination: MapDefinition = catalog.resolve_target(transition, source.world_id)
			if destination == null:
				continue
			var landing: Dictionary = LandingResolverScript.resolve_landing(
				source,
				transition,
				destination,
			)
			_expect(not landing.is_empty(), "内部边缺少落点：%s/%s" % [source.map_id, transition.transition_id])
			if landing.is_empty():
				continue
			if landing.get("evidence") == "reciprocal_exit":
				reciprocal_landings += 1
			elif landing.get("evidence") == "wrapped_field_edge":
				wrapped_landings += 1
			else:
				fallback_landings += 1
			var navigation = _navigation_for(destination)
			_expect(navigation != null, "目标地图导航无法加载：%s" % destination.map_id)
			if navigation != null:
				var audited_position: Vector2 = landing["position"]
				if not navigation.is_walkable(audited_position):
					var corrected_position: Vector2 = navigation.closest_walkable_position(audited_position)
					_expect(
						corrected_position.is_finite()
							and corrected_position.distance_to(audited_position) <= 192.0,
						"连续落点附近没有可走格：%s/%s → %s %s" % [
							source.map_id,
							transition.transition_id,
							destination.map_id,
							audited_position,
						],
					)
					if corrected_position.is_finite():
						audited_position = corrected_position
						corrected_landings += 1
				_expect(
					navigation.is_walkable(audited_position),
					"修正后的连续落点不可行走：%s/%s → %s %s" % [
						source.map_id,
						transition.transition_id,
						destination.map_id,
						audited_position,
					],
				)
	_expect(reciprocal_landings > 0, "全量地图图谱必须识别出双向连续边")
	_expect(wrapped_landings > 0, "缺少反向边的野外地图必须采用边缘连续映射")
	_finish()


## 按地图缓存并返回导航实例，避免同一目标的多条边重复解析网格。
## [param definition] 需要校验落点的目标地图定义。
## 返回已加载导航；资源损坏时返回空值。
func _navigation_for(definition: MapDefinition):
	if navigation_by_map_id.has(definition.map_id):
		return navigation_by_map_id[definition.map_id]
	var navigation = NavigationScript.new()
	if not navigation.load_from(
		definition.navigation_data_path,
		definition.navigation_grid_size,
		definition.navigation_cell_size,
	):
		return null
	navigation_by_map_id[definition.map_id] = navigation
	return navigation


## 汇总全量地图落点审计并设置进程退出码。
func _finish() -> void:
	if failures.is_empty():
		print(
			"GLORY_TRANSITION_LANDING_AUDIT_OK (%d assertions, %d reciprocal, %d wrapped, %d fallback, %d corrected)"
			% [
				assertions,
				reciprocal_landings,
				wrapped_landings,
				fallback_landings,
				corrected_landings,
			]
		)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 记录一条全量地图落点约束。
## [param condition] 落点约束是否满足。
## [param message] 断言失败时输出的地图边诊断。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
