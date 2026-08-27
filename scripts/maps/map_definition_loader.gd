class_name MapDefinitionLoader
extends RefCounted

const MapDefinitionScript := preload("res://scripts/maps/map_definition.gd")
const MapTransitionScript := preload("res://scripts/maps/map_transition.gd")
const MapSpawnPointScript := preload("res://scripts/maps/map_spawn_point.gd")

var errors: PackedStringArray = []


## Loads and validates the requested resource data.
## [param path] Resource or movement path consumed by the operation.
## Returns the resolved map model, or null when no match exists.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func load_file(path: String) -> MapDefinition:
	errors.clear()
	if not FileAccess.file_exists(path):
		_add_error("file", "地图配置不存在：%s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_add_error("file", "地图配置无法读取：%s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_add_error("json", "根节点必须是 JSON object：%s" % path)
		return null
	return load_dictionary(parsed)


## Loads and validates the requested resource data.
## [param raw] Serialized input received at the subsystem boundary.
## Returns the resolved map model, or null when no match exists.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func load_dictionary(raw: Dictionary) -> MapDefinition:
	errors.clear()
	var definition: MapDefinition = MapDefinitionScript.new()
	definition.schema_version = int(raw.get("schema_version", 0))
	if definition.schema_version != 1:
		_add_error("schema_version", "只支持 schema_version=1")

	definition.map_id = StringName(String(raw.get("map_id", "")).strip_edges())
	if definition.map_id.is_empty():
		_add_error("map_id", "map_id 不能为空")
	elif not _is_business_id(String(definition.map_id)):
		_add_error("map_id", "map_id 只能使用小写业务语义标识")

	definition.display_name = String(raw.get("display_name", "")).strip_edges()
	if definition.display_name.is_empty():
		_add_error("display_name", "display_name 不能为空")
	definition.category = String(raw.get("category", "unknown")).strip_edges()

	var legacy: Variant = raw.get("legacy", {})
	if legacy is Dictionary:
		var seen_legacy := {}
		var raw_codes: Variant = legacy.get("codes", [])
		if not raw_codes is Array:
			_add_error("legacy.codes", "legacy.codes 必须是 array")
			raw_codes = []
		for value in raw_codes:
			var code := String(value).strip_edges().to_lower()
			if code.is_empty():
				_add_error("legacy.codes", "旧地图代码不能为空字符串")
			elif seen_legacy.has(code):
				_add_error("legacy.codes", "旧地图代码重复：%s" % code)
			else:
				seen_legacy[code] = true
				definition.legacy_codes.append(code)
	else:
		_add_error("legacy", "legacy 必须是 object")

	var world: Variant = raw.get("world", {})
	if not world is Dictionary:
		_add_error("world", "world 必须是 object")
		world = {}
	definition.world_size = _read_vector2(world.get("size", []), "world.size", true)
	var navigation: Variant = world.get("navigation", {})
	if not navigation is Dictionary:
		_add_error("world.navigation", "navigation 必须是 object")
		navigation = {}
	definition.navigation_grid_size = _read_vector2i(
		navigation.get("grid_size", []), "world.navigation.grid_size", true
	)
	definition.navigation_cell_size = _read_vector2(
		navigation.get("cell_size", []), "world.navigation.cell_size", true
	)
	definition.navigation_data_path = String(navigation.get("data_path", ""))
	if not definition.navigation_data_path.is_empty() and not definition.navigation_data_path.begins_with("res://"):
		_add_error("world.navigation.data_path", "运行时数据路径必须使用 res://")

	var assets: Variant = raw.get("assets", {})
	if not assets is Dictionary:
		_add_error("assets", "assets 必须是 object")
		assets = {}
	var raw_asset_ids: Variant = assets.get("ids", {})
	if raw_asset_ids is Dictionary:
		for key in raw_asset_ids:
			var asset_id := String(raw_asset_ids[key])
			if not _is_business_asset_id(asset_id):
				_add_error("assets.ids.%s" % key, "asset_id 必须是业务语义路径：%s" % asset_id)
			else:
				definition.asset_ids[String(key)] = asset_id
	else:
		_add_error("assets.ids", "assets.ids 必须是 object")
	var raw_paths: Variant = assets.get("resources", {})
	if raw_paths is Dictionary:
		for key in raw_paths:
			var resource_path := String(raw_paths[key])
			if not resource_path.is_empty() and not resource_path.begins_with("res://"):
				_add_error("assets.resources.%s" % key, "运行时资源路径必须使用 res://")
			else:
				definition.resource_paths[String(key)] = resource_path
	else:
		_add_error("assets.resources", "assets.resources 必须是 object")

	# Spawn data was introduced after the first map fixtures; absence remains a
	# valid legacy definition, while every newly promoted runtime map supplies it.
	if raw.has("spawn_points"):
		_load_spawn_points(raw["spawn_points"], definition)
	if raw.has("navigation_overrides"):
		_load_navigation_overrides(raw["navigation_overrides"], definition)

	var raw_source_audit: Variant = raw.get("source_audit", {})
	_validate_source_audit(raw_source_audit, "source_audit")
	if raw_source_audit is Dictionary:
		definition.source_audit = raw_source_audit.duplicate(true)

	var raw_transitions: Variant = raw.get("transitions", [])
	if not raw_transitions is Array:
		_add_error("transitions", "transitions 必须是 array；无出口地图请使用空数组")
		raw_transitions = []
	var transition_ids := {}
	for index in range(raw_transitions.size()):
		if not raw_transitions[index] is Dictionary:
			_add_error("transitions[%d]" % index, "跳转必须是 object")
			continue
		var transition := _load_transition(raw_transitions[index], index, definition.world_size)
		if transition.transition_id.is_empty():
			continue
		if transition_ids.has(transition.transition_id):
			_add_error(
				"transitions[%d].transition_id" % index,
				"同一地图的 transition_id 重复：%s" % transition.transition_id,
			)
		else:
			transition_ids[transition.transition_id] = true
			definition.transitions.append(transition)

	return definition if errors.is_empty() else null


## 读取并校验 [param raw] 中的默认出生点及普通传送入口映射，写入 [param definition]。
## Design: 出生点是新服务端配置；evidence_level 明确区分原客户端证据与重建默认。
func _load_spawn_points(raw: Variant, definition: MapDefinition) -> void:
	if not raw is Dictionary:
		_add_error("spawn_points", "spawn_points 必须是 object")
		return
	definition.default_spawn_id = StringName(String(raw.get("default_id", "")).strip_edges())
	if definition.default_spawn_id.is_empty():
		_add_error("spawn_points.default_id", "默认出生点 ID 不能为空")
	elif not _is_business_id(String(definition.default_spawn_id)):
		_add_error("spawn_points.default_id", "默认出生点 ID 必须是小写业务语义标识")

	var points: Variant = raw.get("points", [])
	if not points is Array or points.is_empty():
		_add_error("spawn_points.points", "至少需要一个出生点")
		return
	var seen_ids := {}
	var seen_entries := {}
	for index in range(points.size()):
		var prefix := "spawn_points.points[%d]" % index
		if not points[index] is Dictionary:
			_add_error(prefix, "出生点必须是 object")
			continue
		var point_raw: Dictionary = points[index]
		var spawn_point: MapSpawnPoint = MapSpawnPointScript.new()
		spawn_point.spawn_id = StringName(String(point_raw.get("spawn_id", "")).strip_edges())
		if spawn_point.spawn_id.is_empty() or not _is_business_id(String(spawn_point.spawn_id)):
			_add_error(prefix + ".spawn_id", "出生点 ID 必须是小写业务语义标识")
		elif seen_ids.has(spawn_point.spawn_id):
			_add_error(prefix + ".spawn_id", "出生点 ID 重复：%s" % spawn_point.spawn_id)
		else:
			seen_ids[spawn_point.spawn_id] = true

		var raw_entry: Variant = point_raw.get("entry_number", null)
		if raw_entry != null and not (raw_entry is int or raw_entry is float):
			_add_error(prefix + ".entry_number", "入口号必须是非负整数或 null")
		elif raw_entry is float and not is_equal_approx(raw_entry, roundf(raw_entry)):
			_add_error(prefix + ".entry_number", "入口号不能包含小数")
		spawn_point.entry_number = -1 if raw_entry == null else int(raw_entry)
		if spawn_point.entry_number < -1:
			_add_error(prefix + ".entry_number", "入口号不能小于零")
		elif spawn_point.entry_number >= 0 and seen_entries.has(spawn_point.entry_number):
			_add_error(prefix + ".entry_number", "入口号重复：%d" % spawn_point.entry_number)
		elif spawn_point.entry_number >= 0:
			seen_entries[spawn_point.entry_number] = true
		spawn_point.position = _read_map_point(
			point_raw.get("position", []), prefix + ".position", definition.world_size
		)
		spawn_point.enabled = bool(point_raw.get("enabled", true))
		spawn_point.evidence_level = String(
			point_raw.get("evidence_level", "reconstructed_default")
		).strip_edges()
		if not spawn_point.evidence_level in [
			"source_confirmed", "navigation_derived", "reconstructed_default"
		]:
			_add_error(prefix + ".evidence_level", "未知证据等级：%s" % spawn_point.evidence_level)
		var audit: Variant = point_raw.get("source_audit", {})
		_validate_source_audit(audit, prefix + ".source_audit")
		if audit is Dictionary:
			spawn_point.source_audit = audit.duplicate(true)
		definition.spawn_points.append(spawn_point)

	if not definition.default_spawn_id.is_empty() and not seen_ids.has(definition.default_spawn_id):
		_add_error("spawn_points.default_id", "默认出生点未出现在 points 中")


## 读取 [param raw] 中声明的动态导航覆盖元数据并写入 [param definition]。
## Design: 本阶段只建立接口，空数组表示目标地图没有已确认的 SetGoFlag 动态规则。
func _load_navigation_overrides(raw: Variant, definition: MapDefinition) -> void:
	if not raw is Array:
		_add_error("navigation_overrides", "navigation_overrides 必须是 array")
		return
	var seen_ids := {}
	for index in range(raw.size()):
		var prefix := "navigation_overrides[%d]" % index
		if not raw[index] is Dictionary:
			_add_error(prefix, "导航覆盖必须是 object")
			continue
		var override: Dictionary = raw[index].duplicate(true)
		var override_id := String(override.get("override_id", "")).strip_edges()
		if not _is_business_id(override_id):
			_add_error(prefix + ".override_id", "导航覆盖 ID 必须是小写业务语义标识")
		elif seen_ids.has(override_id):
			_add_error(prefix + ".override_id", "导航覆盖 ID 重复：%s" % override_id)
		else:
			seen_ids[override_id] = true
		definition.navigation_overrides.append(override)


## Loads and validates the requested resource data.
## [param raw] Serialized input received at the subsystem boundary.
## [param index] Sequence, tick, or index value used by the operation.
## [param world_size] Input value consumed by the operation.
## Returns the resolved map model, or null when no match exists.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func _load_transition(raw: Dictionary, index: int, world_size: Vector2) -> MapTransition:
	var prefix := "transitions[%d]" % index
	var transition: MapTransition = MapTransitionScript.new()
	transition.transition_id = StringName(String(raw.get("transition_id", "")).strip_edges())
	if transition.transition_id.is_empty():
		_add_error(prefix + ".transition_id", "transition_id 不能为空")
	elif not _is_business_id(String(transition.transition_id)):
		_add_error(prefix + ".transition_id", "transition_id 只能使用小写业务语义标识")

	var kind_name := String(raw.get("kind", "standard"))
	match kind_name:
		"standard":
			transition.kind = MapTransitionScript.Kind.STANDARD
		"multi_choice":
			transition.kind = MapTransitionScript.Kind.MULTI_CHOICE
		"client_point":
			transition.kind = MapTransitionScript.Kind.CLIENT_POINT
		"client_line":
			transition.kind = MapTransitionScript.Kind.CLIENT_LINE
		_:
			_add_error(prefix + ".kind", "未知跳转类型：%s" % kind_name)

	transition.enabled = bool(raw.get("enabled", true))
	transition.label = String(raw.get("label", ""))
	transition.source_anchor = _read_map_point(raw.get("source_anchor", []), prefix + ".source_anchor", world_size)
	transition.approach_point = _read_map_point(raw.get("approach_point", []), prefix + ".approach_point", world_size)

	var destination: Variant = raw.get("destination", {})
	if not destination is Dictionary:
		_add_error(prefix + ".destination", "destination 必须是 object")
		destination = {}
	transition.destination_map_id = StringName(String(destination.get("map_id", "")).strip_edges())
	transition.destination_legacy_code = String(destination.get("legacy_code", "")).strip_edges().to_lower()
	transition.destination_entry_number = int(destination.get("entry_number", 0))
	transition.external_target = bool(destination.get("external", false))
	if transition.destination_map_id.is_empty() and transition.destination_legacy_code.is_empty():
		_add_error(prefix + ".destination", "目标必须提供 map_id 或 legacy_code")
	if destination.has("landing_point"):
		transition.destination_landing_point = _read_vector2(
			destination["landing_point"], prefix + ".destination.landing_point", false
		)
		if transition.destination_landing_point.x < 0.0 or transition.destination_landing_point.y < 0.0:
			_add_error(prefix + ".destination.landing_point", "目标落点不能是负坐标")
		transition.has_destination_landing_point = true

	var raw_source_audit: Variant = raw.get("source_audit", {})
	_validate_source_audit(raw_source_audit, prefix + ".source_audit")
	if raw_source_audit is Dictionary:
		transition.source_audit = raw_source_audit.duplicate(true)
	return transition


## Performs the `read_map_point` operation.
## [param value] New value requested by the caller.
## [param field] Input value consumed by the operation.
## [param world_size] Input value consumed by the operation.
## Returns the resolved coordinate.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func _read_map_point(value: Variant, field: String, world_size: Vector2) -> Vector2:
	var point := _read_vector2(value, field, false)
	if point.x < 0.0 or point.y < 0.0 or point.x > world_size.x or point.y > world_size.y:
		_add_error(field, "坐标 %s 超出地图范围 %s" % [point, world_size])
	return point


## Performs the `read_vector2` operation.
## [param value] New value requested by the caller.
## [param field] Input value consumed by the operation.
## [param positive] Whether the corresponding behavior is enabled.
## Returns the resolved coordinate.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func _read_vector2(value: Variant, field: String, positive: bool) -> Vector2:
	if not value is Array or value.size() != 2:
		_add_error(field, "必须是 [x, y]")
		return Vector2.ZERO
	if not (value[0] is int or value[0] is float) or not (value[1] is int or value[1] is float):
		_add_error(field, "坐标必须是数字")
		return Vector2.ZERO
	var result := Vector2(float(value[0]), float(value[1]))
	if not is_finite(result.x) or not is_finite(result.y):
		_add_error(field, "坐标必须是有限数值")
	if positive and (result.x <= 0.0 or result.y <= 0.0):
		_add_error(field, "尺寸必须大于零")
	return result


## Performs the `read_vector2i` operation.
## [param value] New value requested by the caller.
## [param field] Input value consumed by the operation.
## [param positive] Whether the corresponding behavior is enabled.
## Returns the resolved coordinate.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func _read_vector2i(value: Variant, field: String, positive: bool) -> Vector2i:
	var vector := _read_vector2(value, field, positive)
	if vector.x != floorf(vector.x) or vector.y != floorf(vector.y):
		_add_error(field, "网格尺寸必须是整数")
	return Vector2i(roundi(vector.x), roundi(vector.y))


## Validates the supplied state against the domain invariants.
## [param audit] Input value consumed by the operation.
## [param field] Input value consumed by the operation.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func _validate_source_audit(audit: Variant, field: String) -> void:
	if not audit is Dictionary:
		_add_error(field, "source_audit 必须是 object")
		return
	for required_key in ["source_release", "source_map_code", "source_output"]:
		if String(audit.get(required_key, "")).strip_edges().is_empty():
			_add_error(field + "." + required_key, "溯源字段不能为空")


## Reports whether the requested condition is satisfied.
## [param value] New value requested by the caller.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func _is_business_id(value: String) -> bool:
	if value.is_empty() or value != value.to_lower():
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true


## Reports whether the requested condition is satisfied.
## [param value] New value requested by the caller.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func _is_business_asset_id(value: String) -> bool:
	if value.is_empty() or value != value.to_lower():
		return false
	for forbidden in ["pic/", "pic2/", ".ale", "nft_", "chn_", "\\"]:
		if forbidden in value:
			return false
	var segments := value.split("/", false)
	if segments.size() < 2:
		return false
	for segment in segments:
		if not _is_business_id(segment):
			return false
		if _looks_like_timestamped_source_name(segment):
			return false
	return true


## Performs the `looks_like_timestamped_source_name` operation.
## [param segment] Input value consumed by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func _looks_like_timestamped_source_name(segment: String) -> bool:
	# Original ALE exports often use YYYY_MM_DD... names. Those belong only in
	# source_audit and must never leak into a runtime asset ID.
	return (
		segment.length() >= 10
		and segment.substr(0, 4).is_valid_int()
		and segment.substr(4, 1) == "_"
		and segment.substr(5, 2).is_valid_int()
		and segment.substr(7, 1) == "_"
		and segment.substr(8, 2).is_valid_int()
	)


## Mutates the managed collection for the requested value.
## [param field] Input value consumed by the operation.
## [param message] Serialized input received at the subsystem boundary.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func _add_error(field: String, message: String) -> void:
	errors.append("%s: %s" % [field, message])
