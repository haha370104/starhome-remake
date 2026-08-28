class_name MapTransitionMarkerCatalog
extends RefCounted

const DEFAULT_CATALOG_PATH := "res://data/presentation/map_transition_marker_catalog.json"

var _markers: Dictionary = {}


## 加载共享传送点表现目录，并校验八方向资源的基础结构。
## 返回：[enum Error]；成功时返回 [constant OK]，文件或结构无效时返回对应错误码。
## 设计：地图配置只保留方向，资源路径、帧数和固定命中框统一由此目录管理。
func load_default() -> Error:
	if not FileAccess.file_exists(DEFAULT_CATALOG_PATH):
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_CATALOG_PATH))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		return ERR_INVALID_DATA
	var markers_value: Variant = parsed.get("markers", {})
	if not markers_value is Dictionary or (markers_value as Dictionary).size() != 8:
		return ERR_INVALID_DATA
	for orientation_value: Variant in markers_value:
		var orientation := String(orientation_value)
		var marker_value: Variant = (markers_value as Dictionary)[orientation_value]
		if not marker_value is Dictionary or not _is_valid_marker(orientation, marker_value):
			return ERR_INVALID_DATA
	_markers = (markers_value as Dictionary).duplicate(true)
	return OK


## 将地图声明的方向和世界锚点解析为可直接渲染的传送点表现。
## [param orientation] 八方向业务标识，例如 [code]south_west[/code]。
## [param anchor] 传送点在地图世界坐标中的左上锚点。
## 返回：完整表现字典；目录未加载或方向不存在时返回空字典。
func resolve(orientation: StringName, anchor: Vector2) -> Dictionary:
	var orientation_key := String(orientation)
	if not _markers.has(orientation_key):
		return {}
	var result: Dictionary = _markers[orientation_key].duplicate(true)
	result["kind"] = "animated_sprite"
	result["anchor"] = [anchor.x, anchor.y]
	result["sort_baseline"] = anchor.y
	result["activation"] = "enabled_transition"
	return result


## 校验一条共享传送点资源记录是否可被运行时安全消费。
## [param orientation] 当前记录的八方向业务标识。
## [param marker] 待校验的资源、动画和交互元数据。
## 返回：字段完整且业务路径可加载时为 [code]true[/code]。
func _is_valid_marker(orientation: String, marker: Dictionary) -> bool:
	if orientation not in [
		"east", "south_east", "south", "south_west",
		"west", "north_west", "north", "north_east",
	]:
		return false
	var resource_path := String(marker.get("resource", ""))
	var interaction: Variant = marker.get("interaction_rect", [])
	return (
		String(marker.get("asset_id", "")).begins_with("maps/shared/directional_transitions/")
		and resource_path.begins_with("res://assets/maps/shared/directional_transitions/")
		and ResourceLoader.exists(resource_path)
		and String(marker.get("animation", "")).is_empty() == false
		and interaction is Array
		and (interaction as Array).size() == 4
		and int(marker.get("frame_count", 0)) > 0
		and int(marker.get("frame_duration_ms", 0)) > 0
	)
