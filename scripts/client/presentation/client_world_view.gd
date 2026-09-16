class_name ClientWorldView
extends Node2D

const CombatActions := preload("res://scripts/client/gameplay/client_combat_actions.gd")
const COMBAT_VISUAL_MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"
const MINING_VISUAL_MANIFEST_PATH := "res://assets/minerals/mining_asset_manifest.json"
const CharacterFactoryScript := preload("res://scripts/characters/character_factory.gd")
const PlayerWorldAvatarScript := preload("res://scripts/characters/player_world_avatar.gd")
const MovementClickEffectPresenterScript := preload(
	"res://scripts/client/presentation/movement_click_effect_presenter.gd"
)
const WeaponAttackVisualControllerScript := preload(
	"res://scripts/client/presentation/combat/weapon_attack_visual_controller.gd"
)
const MonsterWorldControllerScript := preload(
	"res://scripts/client/presentation/combat/monster_world_controller.gd"
)
const GroundLootWorldControllerScript := preload(
	"res://scripts/client/presentation/combat/ground_loot_world_controller.gd"
)
const MineralWorldControllerScript := preload(
	"res://scripts/client/presentation/mining/mineral_world_controller.gd"
)
const SelfRepairVisualControllerScript := preload(
	"res://scripts/client/presentation/combat/self_repair_visual_controller.gd"
)
const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")
var sortable_world: Node2D
var map_background: Sprite2D
var player: Node2D
var camera: Camera2D
var movement_click_effects: MovementClickEffectPresenter
var combat_attack_controller: Node
var combat_attack_controllers: Dictionary = {}
var monster_world_controller: MonsterWorldController
var ground_loot_world_controller: GroundLootWorldController
var mineral_world_controller: MineralWorldController
var self_repair_visual_controller: SelfRepairVisualController
var mining_visual_controller = preload("res://scripts/client/presentation/mining/mining_visual_controller.gd").new()
var item_catalog: ItemCatalog


## 创建共享玩家锚点，并同时准备人形与按地图切换的战车表现。
## [param character_catalog] 已加载的角色素材目录。
## [param animation_speed] 本地角色动画倍率。
func configure(character_catalog: Dictionary, animation_speed: float) -> void:
	map_background = Sprite2D.new()
	map_background.name = "MapBase"
	map_background.centered = false
	map_background.position = Vector2.ZERO
	map_background.z_index = -100
	add_child(map_background)

	movement_click_effects = MovementClickEffectPresenterScript.new()
	movement_click_effects.name = "MovementClickEffects"
	movement_click_effects.z_index = -20
	add_child(movement_click_effects)

	sortable_world = Node2D.new()
	sortable_world.name = "YSortedWorld"
	sortable_world.y_sort_enabled = true
	add_child(sortable_world)

	player = PlayerWorldAvatarScript.new()
	player.name = "Player"
	var combat_manifest_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(COMBAT_VISUAL_MANIFEST_PATH)
	)
	var combat_manifest: Dictionary = {}
	if combat_manifest_value is Dictionary:
		combat_manifest = combat_manifest_value
	var avatar_error: Error = player.configure(
		CharacterFactoryScript.build_character_set(character_catalog, "player"),
		combat_manifest,
		"H番茄花园",
		Color(0.35, 1.0, 0.92),
		PlayerWorldAvatarScript.HUMAN_NAME_LABEL_POSITION,
	)
	if avatar_error != OK:
		push_error("Unable to configure player avatar: %s" % error_string(avatar_error))
	player.set_animation_speed_scale(animation_speed)
	sortable_world.add_child(player)

	for mode_id: String in CombatActions.WEAPON_MODES:
		var mode: Dictionary = CombatActions.WEAPON_MODES[mode_id]
		var controller := WeaponAttackVisualControllerScript.new()
		controller.name = "%sAttackVisualController" % mode_id.to_pascal_case()
		add_child(controller)
		var attack_visual_error: Error = controller.configure(
			combat_manifest, sortable_world, StringName(mode["weapon_id"])
		)
		if attack_visual_error != OK:
			push_error("Unable to configure %s visuals: %s" % [
				mode_id, error_string(attack_visual_error),
			])
			controller.free()
			continue
		combat_attack_controllers[mode_id] = controller
	combat_attack_controller = combat_attack_controllers.get("energy_cannon")
	monster_world_controller = MonsterWorldControllerScript.new()
	monster_world_controller.name = "MonsterWorldController"
	add_child(monster_world_controller)
	var monster_error := monster_world_controller.configure(sortable_world, combat_manifest, player)
	if monster_error != OK:
		push_error("Unable to configure monster world presentation: %s" % error_string(monster_error))
	else:
		for controller: Node in combat_attack_controllers.values():
			controller.set_visual_collision_resolver(monster_world_controller.first_visual_collision)
	item_catalog = ItemCatalogScript.new()
	var item_catalog_result := item_catalog.initialize()
	if item_catalog_result.is_ok:
		ground_loot_world_controller = GroundLootWorldControllerScript.new()
		ground_loot_world_controller.name = "GroundLootWorldController"
		add_child(ground_loot_world_controller)
		var loot_error := ground_loot_world_controller.configure(
			sortable_world,
			item_catalog,
		)
		if loot_error != OK:
			push_error("Unable to configure ground loot presentation: %s" % error_string(loot_error))
	else:
		push_error("Unable to load shared item catalog: %s" % item_catalog_result.error_message)
	var mining_manifest_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(MINING_VISUAL_MANIFEST_PATH)
	)
	if mining_manifest_value is Dictionary:
		mineral_world_controller = MineralWorldControllerScript.new()
		mineral_world_controller.name = "MineralWorldController"
		add_child(mineral_world_controller)
		var mining_error := mineral_world_controller.configure(
			sortable_world,
			mining_manifest_value,
		)
		if mining_error != OK:
			push_error("Unable to configure mineral presentation: %s" % error_string(mining_error))
	else:
		push_error("Unable to load mineral presentation manifest")

	camera = Camera2D.new()
	camera.name = "PlayerCamera"
	camera.position = player.position
	# 原客户端按 ALE 与地图像素 1:1 绘制；窗口变大只扩大视野，不缩放世界内容。
	camera.zoom = Vector2.ONE
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = 0
	camera.limit_bottom = 0
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.5
	add_child(camera)
	camera.make_current()
	mining_visual_controller.configure(player)
	self_repair_visual_controller = SelfRepairVisualControllerScript.new()
	self_repair_visual_controller.name = "SelfRepairVisualController"
	add_child(self_repair_visual_controller)
	var repair_error := self_repair_visual_controller.configure(player)
	if repair_error != OK:
		push_error("Unable to configure self-repair presentation: %s" % error_string(repair_error))


## 在活动地图替换前清除旧世界的临时特效与实体视图。
func clear_map_effects() -> void:
	if movement_click_effects != null:
		movement_click_effects.clear_effects()
	for controller: Node in combat_attack_controllers.values():
		controller.clear_effects()
	if monster_world_controller != null:
		monster_world_controller.clear()
	if mineral_world_controller != null:
		mineral_world_controller.clear()
	mining_visual_controller.clear()


## 用同一玩家装配选择各攻击槽的后续弹体，工程臂和空槽不保留旧炮表现。
## [param vehicle] 当前玩家战车聚合；不会写入任何权威状态。
func apply_weapon_equipment(vehicle: PlayerVehicle) -> void:
	for mode_id: String in combat_attack_controllers:
		var equipment := vehicle.loadout.at(1 if mode_id == "energy_cannon" else 13) as VehicleWeapon
		var weapon_id := StringName(equipment.definition_id) if equipment != null and equipment.combat_mode() == mode_id else &""
		combat_attack_controllers[mode_id].select_weapon(weapon_id)
