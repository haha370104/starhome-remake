class_name ActiveWorldController
extends Node

signal active_world_will_replace

const DiamondNavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")
const MapDefinitionLoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const CharacterFactoryScript := preload("res://scripts/characters/character_factory.gd")
const YSortedPropScript := preload("res://scripts/world/y_sorted_prop.gd")
const SemanticSceneLayerScript := preload("res://scripts/world/semantic_scene_layer.gd")
const NpcBaseScript := preload("res://scripts/npcs/npc_base.gd")
const ShopNpcScript := preload("res://scripts/npcs/shop_npc.gd")
const QuestNpcScript := preload("res://scripts/npcs/quest_npc.gd")
const TransitionViewScript := preload("res://scripts/client/world/map_transition_view.gd")

var definition: MapDefinition
var navigation: RefCounted
var map_manifest: Dictionary = {}
var map_size := Vector2.ZERO
var scene_nodes: Array[Node2D] = []
var npc_instances: Array[Node2D] = []
var transition_views: Array[Node2D] = []

var _world_root: Node2D
var _sortable_world: Node2D
var _background: Sprite2D
var _player_avatar: Node2D
var _local_player_controller: Node
var _camera: Camera2D
var _hud: CanvasLayer
var _character_catalog: Dictionary = {}
var _npc_catalog: Dictionary = {}


## 绑定活动世界所需的 [param world_root]、[param sortable_world] 与 [param background]。
## [param player_avatar]、[param local_player_controller]、[param camera] 和 [param hud] 是原子提交的唯一表现出口。
## [param character_catalog] 与 [param npc_catalog] 仅用于暂存目标地图 NPC，不由入口脚本解释。
## Returns 依赖完整时返回 `OK`，否则返回 `ERR_INVALID_PARAMETER`。
func configure(
	world_root: Node2D,
	sortable_world: Node2D,
	background: Sprite2D,
	player_avatar: Node2D,
	local_player_controller: Node,
	camera: Camera2D,
	hud: CanvasLayer,
	character_catalog: Dictionary,
	npc_catalog: Dictionary,
) -> Error:
	if (
		world_root == null
		or sortable_world == null
		or background == null
		or player_avatar == null
		or local_player_controller == null
		or camera == null
		or hud == null
	):
		return ERR_INVALID_PARAMETER
	_world_root = world_root
	_sortable_world = sortable_world
	_background = background
	_player_avatar = player_avatar
	_local_player_controller = local_player_controller
	_camera = camera
	_hud = hud
	_character_catalog = character_catalog
	_npc_catalog = npc_catalog
	return OK


## 从受控 [param definition_path] 同步准备初始地图 bundle。
## Returns 定义、场景清单和两张基础纹理全部有效时返回 bundle，否则返回空字典。
## Design: 该入口仅用于应用启动；运行中地图继续使用异步 `ClientMapPreloader`。
func prepare_initial_bundle(definition_path: String) -> Dictionary:
	var loader: RefCounted = MapDefinitionLoaderScript.new()
	var staged_definition: MapDefinition = loader.load_file(definition_path)
	if staged_definition == null:
		return {}
	var manifest_path := String(staged_definition.resource_paths.get("scene_manifest", ""))
	if manifest_path.is_empty() or not FileAccess.file_exists(manifest_path):
		return {}
	var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest_value is Dictionary:
		return {}
	var floor_texture := load(String(staged_definition.resource_paths.get("floor", ""))) as Texture2D
	var minimap_texture := load(String(staged_definition.resource_paths.get("minimap", ""))) as Texture2D
	if floor_texture == null or minimap_texture == null:
		return {}
	return {
		"definition": staged_definition,
		"map_manifest": manifest_value,
		"resources": {"floor": floor_texture, "minimap": minimap_texture},
	}


## 完整暂存并原子提交 [param bundle]，最后把玩家放到权威 [param spawn_position]。
## Returns 导航、场景、NPC、传送视图和基础资源全部有效时返回 `true`。
## Design: 所有加载与节点构建先发生在离树暂存容器；失败不会清理或改写当前活动世界。
func commit_bundle(bundle: Dictionary, spawn_position: Vector2) -> bool:
	var staged := _stage_bundle(bundle, spawn_position)
	if staged.is_empty():
		return false
	if _player_avatar.apply_map_presentation(staged["player_presentation"]) != OK:
		staged["container"].free()
		return false
	active_world_will_replace.emit()
	_clear_active_nodes()
	definition = staged["definition"]
	navigation = staged["navigation"]
	map_manifest = staged["map_manifest"]
	map_size = definition.world_size
	scene_nodes = staged["scene_nodes"]
	npc_instances = staged["npc_instances"]
	transition_views = staged["transition_views"]
	_adopt_staged_nodes(staged["container"])
	_background.texture = staged["floor_texture"]
	_local_player_controller.commit_map_position(navigation, spawn_position)
	_camera.limit_right = int(map_size.x)
	_camera.limit_bottom = int(map_size.y)
	_camera.position = spawn_position
	_hud.set_map(map_size, staged["minimap_texture"], definition.display_name)
	return true


## 返回世界坐标 [param world_position] 命中的最上层传送视图。
## Returns 命中时返回业务 transition view，否则返回 `null`。
func transition_view_at(world_position: Vector2) -> Node2D:
	for index in range(transition_views.size() - 1, -1, -1):
		var view := transition_views[index]
		if view.hit_test(world_position):
			return view
	return null


## 返回业务标识 [param transition_id] 对应的活动传送视图。
## Returns 当前地图存在该视图时返回节点，否则返回 `null`。
func transition_view_by_id(transition_id: StringName) -> Node2D:
	for view in transition_views:
		if view.transition_id == transition_id:
			return view
	return null


## 暂存 [param bundle] 的全部可失败依赖，并校验 [param spawn_position] 可行走。
## Returns 成功时返回只待收养的节点和资源，失败时释放暂存容器并返回空字典。
func _stage_bundle(bundle: Dictionary, spawn_position: Vector2) -> Dictionary:
	var staged_definition: MapDefinition = bundle.get("definition")
	var staged_manifest: Dictionary = bundle.get("map_manifest", {})
	var resources: Dictionary = bundle.get("resources", {})
	var floor_texture := resources.get("floor") as Texture2D
	var minimap_texture := resources.get("minimap") as Texture2D
	if staged_definition == null or staged_manifest.is_empty() or floor_texture == null or minimap_texture == null:
		return {}
	var staged_navigation := DiamondNavigationScript.new()
	if not staged_navigation.load_from(
		staged_definition.navigation_data_path,
		staged_definition.navigation_grid_size,
		staged_definition.navigation_cell_size,
	):
		return {}
	if not staged_navigation.is_walkable(spawn_position):
		return {}
	if _player_avatar.validate_map_presentation(staged_definition.player_presentation) != OK:
		return {}
	var container := Node2D.new()
	container.name = "StagedMapContent"
	var staged_scene_nodes: Array[Node2D] = []
	var staged_npcs: Array[Node2D] = []
	var staged_transition_views: Array[Node2D] = []
	if not _stage_scene_nodes(staged_manifest, container, staged_scene_nodes):
		container.free()
		return {}
	if not _stage_npcs(staged_definition, staged_navigation, container, staged_npcs):
		container.free()
		return {}
	if not _stage_transition_views(staged_definition, container, staged_transition_views):
		container.free()
		return {}
	return {
		"definition": staged_definition,
		"navigation": staged_navigation,
		"map_manifest": staged_manifest,
		"floor_texture": floor_texture,
		"minimap_texture": minimap_texture,
		"player_presentation": staged_definition.player_presentation.duplicate(true),
		"container": container,
		"scene_nodes": staged_scene_nodes,
		"npc_instances": staged_npcs,
		"transition_views": staged_transition_views,
	}


## 在 [param container] 中构建 [param manifest] 的语义场景节点并写入 [param output]。
## Returns 所有纹理和字段有效时返回 `true`。
func _stage_scene_nodes(manifest: Dictionary, container: Node2D, output: Array[Node2D]) -> bool:
	var composition_value: Variant = manifest.get("composition", {})
	if not composition_value is Dictionary:
		return false
	var composition: Dictionary = composition_value
	if String(composition.get("render_strategy", "")) == "semantic_owner_layers":
		var layers_value: Variant = composition.get("semantic_layers", [])
		if not layers_value is Array:
			return false
		for index in range((layers_value as Array).size()):
			var layer_definition: Dictionary = (layers_value as Array)[index]
			var texture := load(String(layer_definition.get("texture", ""))) as Texture2D
			var offset: Array = layer_definition.get("pixel_offset", [])
			var atlas_values: Array = layer_definition.get("atlas_region", [])
			if texture == null or offset.size() != 2 or atlas_values.size() != 4:
				return false
			var layer: Node2D = SemanticSceneLayerScript.new()
			layer.name = "SemanticSceneLayer_%d" % (index + 1)
			layer.configure(
				texture,
				Rect2(float(atlas_values[0]), float(atlas_values[1]), float(atlas_values[2]), float(atlas_values[3])),
				Vector2(float(offset[0]), float(offset[1])),
				float(layer_definition.get("sort_baseline", 0.0)),
			)
			container.add_child(layer)
			output.append(layer)
		return true
	var props_value: Variant = composition.get("props", [])
	if not props_value is Array:
		return false
	for index in range((props_value as Array).size()):
		var prop_definition: Dictionary = (props_value as Array)[index]
		var texture := load(String(prop_definition.get("texture", ""))) as Texture2D
		var anchor_values: Array = prop_definition.get("anchor", [])
		var offset_values: Array = prop_definition.get("offset", [])
		if texture == null or anchor_values.size() != 2 or offset_values.size() != 2:
			return false
		var anchor := Vector2(float(anchor_values[0]), float(anchor_values[1]))
		var prop: Node2D = YSortedPropScript.new()
		prop.name = "SceneProp_%d" % (index + 1)
		prop.configure(
			texture,
			anchor,
			Vector2(float(offset_values[0]), float(offset_values[1])),
			float(prop_definition.get("sort_baseline", anchor.y)),
		)
		container.add_child(prop)
		output.append(prop)
	return true


## 在 [param container] 中按 [param staged_definition] 和 [param staged_navigation] 暂存 NPC。
## [param output] 接收已验证但尚未迁入活动场景的 NPC 节点。
## Returns 当前地图无需 NPC 或全部 NPC 配置成功时返回 `true`。
func _stage_npcs(
	staged_definition: MapDefinition,
	staged_navigation: RefCounted,
	container: Node2D,
	output: Array[Node2D],
) -> bool:
	if staged_definition.map_id != &"yian_harbor_hall_floor_1":
		return true
	for definition_value: Variant in _npc_catalog.get("npcs", []):
		if not definition_value is Dictionary:
			return false
		var npc_definition: Dictionary = definition_value
		var npc := _create_npc_for_kind(String(npc_definition.get("kind", "ambient")))
		var appearance := String(npc_definition.get("appearance", "npc_red"))
		var character_set: Dictionary = CharacterFactoryScript.build_character_set(
			_character_catalog,
			appearance,
		)
		if character_set.is_empty():
			return false
		npc.configure_npc(character_set, npc_definition, staged_navigation)
		container.add_child(npc)
		output.append(npc)
	return true


## 为 [param staged_definition] 中带表现字段的出口在 [param container] 暂存动画视图。
## [param output] 接收已验证但尚未迁入活动场景的传送视图。
## Returns 所有已声明表现的出口均构建成功时返回 `true`；缺省表现暂时保持无视图兼容。
func _stage_transition_views(
	staged_definition: MapDefinition,
	container: Node2D,
	output: Array[Node2D],
) -> bool:
	for transition in staged_definition.enabled_transitions():
		if transition.presentation.is_empty():
			continue
		var view: Node2D = TransitionViewScript.new()
		view.name = "Transition_%s" % String(transition.transition_id).to_pascal_case()
		if view.configure(transition, transition.presentation) != OK:
			view.free()
			return false
		container.add_child(view)
		output.append(view)
	return true


## 根据 [param kind] 创建大厅 NPC 表现节点。
## Returns 对应商店、任务或环境 NPC 节点。
func _create_npc_for_kind(kind: String) -> Node2D:
	match kind:
		"shop":
			return ShopNpcScript.new()
		"quest":
			return QuestNpcScript.new()
		_:
			return NpcBaseScript.new()


## 清理当前活动地图的场景、NPC 和传送视图，不触碰玩家或远端玩家节点。
func _clear_active_nodes() -> void:
	_hud.hide_popup()
	for node in scene_nodes + npc_instances + transition_views:
		if is_instance_valid(node):
			node.free()
	scene_nodes.clear()
	npc_instances.clear()
	transition_views.clear()


## 将 [param container] 的全部暂存子节点迁入活动 Y-sort 世界并释放空容器。
func _adopt_staged_nodes(container: Node2D) -> void:
	for child in container.get_children():
		container.remove_child(child)
		_sortable_world.add_child(child)
	container.free()
