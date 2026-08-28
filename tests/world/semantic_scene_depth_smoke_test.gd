extends SceneTree

const SemanticSceneLayerScript := preload("res://scripts/world/semantic_scene_layer.gd")
const WorldCharacterScript := preload("res://scripts/characters/world_character.gd")
const CharacterFactoryScript := preload("res://scripts/characters/character_factory.gd")
const MANIFEST_PATH := "res://assets/maps/yian_harbor/hall_floor_1/map_manifest.json"
const PROFILE_PATH := "res://assets/maps/yian_harbor/hall_floor_1/depth_profiles/industrial_stairway/depth_profile.json"
const CHARACTER_CATALOG_PATH := "res://assets/characters/character_atlases.json"

var failures: PackedStringArray = []
var assertions := 0


## 初始化当前模块或独立测试夹具。
## 设计：该测试以隔离夹具验证公开契约，不依赖未声明的全局状态。
func _initialize() -> void:
	_test_layer_preserves_cropped_pixel_position()
	_test_manifest_uses_semantic_owners()
	_test_semantic_overlap_order()
	_test_stair_profile_with_real_character()
	_test_stair_masks_partition_asset()
	if failures.is_empty():
		print("SEMANTIC_SCENE_DEPTH_SMOKE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 执行 `test_layer_preserves_cropped_pixel_position` 对应的模块操作。
func _test_layer_preserves_cropped_pixel_position() -> void:
	var layer: Node2D = SemanticSceneLayerScript.new()
	layer.configure(null, Rect2(20, 30, 40, 50), Vector2(120, 896), 993.0)
	var sprite := layer.get_node("Sprite") as Sprite2D
	_expect(layer.position == Vector2(120, 993), "语义层父节点必须位于业务基线")
	_expect(sprite.position == Vector2(0, -97), "裁剪纹理应反向补偿业务基线")
	_expect(layer.position + sprite.position == Vector2(120, 896), "语义层像素位置必须保持不变")
	_expect((sprite.texture as AtlasTexture).region == Rect2(20, 30, 40, 50), "语义层必须使用共享 atlas 的指定区域")
	layer.free()


## 执行 `test_manifest_uses_semantic_owners` 对应的模块操作。
func _test_manifest_uses_semantic_owners() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var composition: Dictionary = manifest["composition"]
	_expect(String(composition["render_strategy"]) == "semantic_owner_layers", "大厅必须使用 owner 语义层")
	_expect(String(composition["semantic_sort_rule"]) == "fcc_source_order_with_profile_depth_overrides", "静态构造应保留 FCC 顺序，仅 profile 遮挡按深度覆盖")
	_expect(not composition.has("depth_bands"), "manifest 不应保留屏幕 Y 深度条带")
	var layers: Array = composition["semantic_layers"]
	_expect(layers.size() > 2 and layers.size() < 350, "语义层节点数应显著低于旧 458 条带")
	_expect(int(composition["semantic_atlas_size"][0]) == 1024, "语义层应共用单张紧凑 atlas")
	_expect(int(composition["semantic_atlas_size"][1]) < 2600, "语义 atlas 显存应显著低于旧全地图纹理")
	for value in layers:
		var layer: Dictionary = value
		var region: Array = layer["region"]
		_expect(region[0] == layer["pixel_offset"][0] and region[1] == layer["pixel_offset"][1], "region 与裁剪偏移必须一致")
		_expect(region[2] == layer["size"][0] and region[3] == layer["size"][1], "region 与裁剪尺寸必须一致")
		_expect(layer.has("atlas_region"), "每个裁剪层必须记录 atlas_region")
		_expect(int(region[2]) < 1944 or int(region[3]) < 1920, "运行时语义层不得是全地图纹理")
		_expect(FileAccess.file_exists(String(layer["texture"])), "每个语义层都必须有裁剪纹理")
	_expect(String(composition["reference_pixel_sha256"]).length() == 64, "必须记录静态 composite 像素哈希")
	_expect(String(composition["scene_pixel_sha256"]).length() == 64, "必须记录透明 scene_color 像素哈希")
	_expect(String(composition["source_order_reference_pixel_sha256"]) == "5515746b14c7dbf6821f61756eb562171e638bde2bc77484fca7b397f8e9b1f9", "FCC 活跃构件基准像素必须保持稳定")
	_expect(String(composition["reference_pixel_sha256"]) == "a051dce4cff6e4bd4b1f3a6d68cf0a83189b222669f8af4ca9cb5532ccd82d32", "profile 修复后的静态像素必须保持稳定")
	_expect(int(composition["profile_override_pixel_count"]) == 1846, "两组扶手 profile 应只接管 1846 个重叠 owner 像素")
	_expect(int(composition["profile_changed_pixel_count"]) == 1828, "扶手 profile 的实际颜色变化像素应保持可审计")
	_expect(int(composition["non_profile_changed_pixel_count"]) == 0, "profile 修复不得改动遮挡交集外的 FCC 静态像素")
	_expect(FileAccess.file_exists(String(composition["source_order_reference"])), "必须保留修复前 FCC source-order 像素基准")
	_expect(FileAccess.file_exists(String(composition["profile_override_mask"])), "必须保留 profile 修复像素范围")
	_expect(FileAccess.file_exists(String(composition["static_composite"])), "必须保留离线静态重建图")
	_expect(int(composition["disabled_placement_count"]) == 16, "应识别 16 条被注释禁用的 FCC 摆放")

	var disabled_indices: Dictionary = {}
	var preserved_extended_call := false
	for value in composition["source_placements"]:
		var placement: Dictionary = value
		if not placement["render_enabled"]:
			disabled_indices[int(placement["source_index"])] = true
		if placement["placement_kind"] == "AddImgEx" and placement["payload"] != null:
			preserved_extended_call = placement.has("numeric_arg_1") and placement.has("numeric_arg_2") and String(placement["payload_raw_hex"]).length() > 0
	_expect(preserved_extended_call, "AddImgEx 的两个数值、payload 与原始字节必须完整保留")
	for value in composition["owner_audit"]:
		var owner: Dictionary = value
		_expect(not disabled_indices.has(int(owner["source_index"])), "被注释禁用的摆放不得拥有运行时像素")


## 执行 `test_semantic_overlap_order` 对应的模块操作。
## 设计：该测试以隔离夹具验证公开契约，不依赖未声明的全局状态。
func _test_semantic_overlap_order() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var composition: Dictionary = manifest["composition"]
	var owners_by_id: Dictionary = {}
	for owner_value in composition["owner_audit"]:
		var owner: Dictionary = owner_value
		owners_by_id[int(owner["owner_id"])] = owner

	var rails_with_later_source_platform_overlap: Dictionary = {}
	for edge_value in composition["semantic_overlap_graph"]:
		var edge: Dictionary = edge_value
		var below: Dictionary = owners_by_id[int(edge["below_owner_id"])]
		var above: Dictionary = owners_by_id[int(edge["above_owner_id"])]
		_expect(int(edge["pixel_count"]) > 0, "遮挡图的每条边必须对应真实重叠像素")
		_expect(int(below["sort_baseline"]) <= int(above["sort_baseline"]), "上层语义基线不得小于被覆盖层")
		if int(below["sort_baseline"]) == int(above["sort_baseline"]):
			_expect(int(below["source_index"]) <= int(above["source_index"]), "同基线构件才可用 FCC 顺序消歧")
		if (
			above["component_id"] == "handrail_occluder"
			and String(above["asset_id"]).ends_with("/stairway")
			and String(below["asset_id"]).contains("/central_platform_")
			and int(below["source_index"]) > int(above["source_index"])
		):
			rails_with_later_source_platform_overlap[int(above["source_index"])] = true
	_expect(rails_with_later_source_platform_overlap.size() == 2, "两组楼梯扶手都必须按基线盖住 FCC 中后创建的高台构件")


## 执行 `test_stair_profile_with_real_character` 对应的模块操作。
func _test_stair_profile_with_real_character() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var composition: Dictionary = manifest["composition"]
	var character_catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHARACTER_CATALOG_PATH))
	var character: Node2D = WorldCharacterScript.new()
	character.configure(
		CharacterFactoryScript.build_character_set(character_catalog, "player"),
		"语义深度测试角色",
		Color.WHITE,
		Vector2(-66, -158),
	)
	_expect(character.get_node("Body") is AnimatedSprite2D, "前后关系测试必须使用真实角色身体动画")
	_expect(character.get_node("Equipment") is AnimatedSprite2D, "前后关系测试必须使用真实角色装备动画")

	var lower_tread_baseline := 0
	var lower_rail_baseline := 0
	var upper_rail_baseline := 0
	for value in composition["owner_audit"]:
		var owner: Dictionary = value
		if owner["asset_id"] != "maps/yian_harbor/hall_floor_1/props/stairway":
			continue
		if int(owner["source_index"]) == 81 and owner["component_id"] == "tread_underlay":
			lower_tread_baseline = int(owner["sort_baseline"])
		if int(owner["source_index"]) == 81 and owner["component_id"] == "handrail_occluder":
			lower_rail_baseline = int(owner["sort_baseline"])
		if int(owner["source_index"]) == 51 and owner["component_id"] == "handrail_occluder":
			upper_rail_baseline = int(owner["sort_baseline"])

	character.position = Vector2(984, 900)
	_expect(lower_tread_baseline < character.position.y, "角色站在踏板上时踏板必须在角色下方")
	_expect(character.position.y < lower_rail_baseline, "角色位于楼梯后侧时仅扶手应遮挡角色")
	character.position = Vector2(984, 1000)
	_expect(lower_rail_baseline < character.position.y, "角色走到楼梯前侧时必须绘制在扶手之前景上方")
	character.position = Vector2(840, 500)
	_expect(character.position.y < upper_rail_baseline, "上方楼梯也必须复用同一扶手遮挡规则")
	character.position = Vector2(840, 600)
	_expect(upper_rail_baseline < character.position.y, "上方楼梯前侧角色必须显示在扶手上方")

	# Regression point from the real screenshot.  The profile lookup derives the
	# relevant occluder depth from asset-local geometry instead of world patches.
	character.position = Vector2(744, 564)
	var upper_stair: Dictionary = {}
	for prop_value in composition["props"]:
		var prop: Dictionary = prop_value
		if not String(prop["asset_id"]).ends_with("/stairway"):
			continue
		if upper_stair.is_empty() or int(prop["anchor"][1]) < int(upper_stair["anchor"][1]):
			upper_stair = prop
	var stair_top_left := Vector2i(
		int(upper_stair["anchor"][0]) + int(upper_stair["offset"][0]),
		int(upper_stair["anchor"][1]) + int(upper_stair["offset"][1]),
	)
	var depth_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	var depth_field := Image.load_from_file(ProjectSettings.globalize_path(String(depth_profile["components"][1]["depth_field"])))
	var local_x := int(character.position.x) - stair_top_left.x
	var deepest_local_baseline := -1
	for local_y in range(depth_field.get_height()):
		var encoded := int(round(depth_field.get_pixel(local_x, local_y).r * 255.0))
		if encoded > 0:
			deepest_local_baseline = maxi(deepest_local_baseline, encoded - 1)
	_expect(deepest_local_baseline >= 0, "截图角色所在列必须命中扶手局部深度场")
	_expect(stair_top_left.y + deepest_local_baseline < character.position.y, "角色脚点 744,564 必须绘制在该列扶手与最下沿之前")
	character.free()


## 执行 `test_stair_masks_partition_asset` 对应的模块操作。
func _test_stair_masks_partition_asset() -> void:
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	_expect(String(profile["profile_id"]) == "industrial_stairway_traversable", "楼梯应使用可复用业务 depth profile")
	_expect(String(profile["mask_generation"]["method"]) == "segmented_column_ground_envelope_quantized", "楼梯遮挡必须来自可审计的资产局部深度场")
	_expect(int(profile["mask_generation"]["depth_quantum"]) == 12, "扶手局部深度场应使用稳定量化步长")
	var tread := Image.load_from_file(ProjectSettings.globalize_path(String(profile["components"][0]["mask"])))
	var rail := Image.load_from_file(ProjectSettings.globalize_path(String(profile["components"][1]["mask"])))
	var source := Image.load_from_file(ProjectSettings.globalize_path("res://assets/maps/yian_harbor/hall_floor_1/props/stairway.png"))
	_expect(tread.get_size() == source.get_size() and rail.get_size() == source.get_size(), "楼梯组件 mask 必须与业务资产同尺寸")
	var exact_partition := true
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var source_visible := source.get_pixel(x, y).a > 0.0
			var tread_visible := tread.get_pixel(x, y).r > 0.5
			var rail_visible := rail.get_pixel(x, y).r > 0.5
			if (tread_visible and rail_visible) or (source_visible != (tread_visible or rail_visible)):
				exact_partition = false
				break
		if not exact_partition:
			break
	_expect(exact_partition, "踏板与扶手 mask 应无重叠且完整覆盖源 alpha")
	_expect(tread.get_pixel(138, 110).r > 0.5, "踏板中央像素应属于 underlay")
	_expect(rail.get_pixel(20, 120).r > 0.5, "左扶手像素应属于 occluder")
	_expect(rail.get_pixel(160, 228).r > 0.5, "前扶手像素应属于 occluder")


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
