class_name PlayerWorldAvatar
extends Node2D

const WorldCharacterScript := preload("res://scripts/characters/world_character.gd")
const CombatVisualPresenterScript := preload(
	"res://scripts/client/presentation/combat/combat_visual_presenter.gd"
)
const WorldCombatStatusBarScript := preload(
	"res://scripts/client/presentation/combat/world_combat_status_bar.gd"
)
const CharacterFactoryScript := preload("res://scripts/characters/character_factory.gd")

const CHARACTER_KIND := &"character"
const COMBAT_ACTOR_KIND := &"combat_actor"
const HUMAN_NAME_LABEL_POSITION := WorldCharacterScript.PLAYER_NAME_LABEL_POSITION
const COMBAT_NAME_LABEL_POSITION := Vector2(-65, -48)

var presentation_kind: StringName = CHARACTER_KIND
var combat_actor_id: StringName = &""
var human_character: Node2D
var combat_presenter: Node2D
var combat_name_label: Label
var combat_status_bar: WorldCombatStatusBar

var _combat_manifest: Dictionary = {}
var _current_action := &"stand"
var _current_direction := 6
var _animation_speed_scale := 1.0
var _vehicle_destroyed := false
var _equipped_combat_actor_id: StringName = &""
var _equipped_chassis_definition_id := ""
var _equipped_primary_definition_id := ""
var _clothing_appearance_key := ""
var _character_sex := "male"
var _public_appearance: Dictionary = {}


## 构建共享人形角色与按需隐藏的战斗载具表现。
## [param character_set] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param combat_manifest] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param display_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param name_color] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param human_name_offset] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func configure(
	character_set: Dictionary,
	combat_manifest: Dictionary,
	display_name: String,
	name_color: Color,
	human_name_offset: Vector2,
) -> Error:
	if character_set.is_empty() or combat_manifest.is_empty():
		return ERR_INVALID_PARAMETER
	_combat_manifest = combat_manifest.duplicate(true)

	human_character = WorldCharacterScript.new()
	human_character.name = "HumanCharacter"
	human_character.configure(
		character_set,
		display_name,
		name_color,
		human_name_offset,
	)
	_character_sex = human_character.body_sex
	human_character.set_equipment_visible(false)
	add_child(human_character)

	combat_presenter = CombatVisualPresenterScript.new()
	combat_presenter.name = "CombatActor"
	var presenter_error: Error = combat_presenter.configure(_combat_manifest)
	if presenter_error != OK:
		return presenter_error
	combat_presenter.visible = false
	add_child(combat_presenter)

	combat_name_label = _build_name_label(display_name, name_color)
	combat_name_label.visible = false
	add_child(combat_name_label)
	combat_status_bar = WorldCombatStatusBarScript.new()
	combat_status_bar.name = "CombatStatusBar"
	combat_status_bar.configure(50.0, true, Vector2(0, 45))
	combat_status_bar.visible = false
	add_child(combat_status_bar)
	return OK

func set_display_name(value: String) -> void:
	human_character.display_name = value
	human_character.name_label.text = value
	combat_name_label.text = value


func get_display_name() -> String:
	return human_character.get_display_name()


func get_combat_manifest() -> Dictionary:
	return _combat_manifest


func hit_test(world_position: Vector2) -> bool:
	if presentation_kind == CHARACTER_KIND:
		return human_character.hit_test(world_position)
	return combat_presenter.hit_test(world_position)


func apply_public_appearance(appearance: Dictionary, items: ItemCatalog, character_catalog: Dictionary) -> bool:
	if appearance == _public_appearance:
		return true
	var clothing := CharacterEquipment.new()
	var vehicle := PlayerVehicle.new()
	for slot: String in ["upper_body", "chassis", "primary_weapon"]:
		var definition_id := String(appearance.get(slot, ""))
		if definition_id.is_empty():
			continue
		var created := items.create(definition_id, {"instance_id": slot})
		if not created.is_ok:
			return false
		var restored := clothing.restore(created.value) if slot == "upper_body" else vehicle.loadout.restore(created.value)
		if not restored.is_ok:
			return false
	set_display_name(String(appearance.get("display_name", get_display_name())))
	if not apply_character_equipment(clothing, character_catalog):
		return false
	if not apply_vehicle_equipment(vehicle) and not String(appearance.get("chassis", "")).is_empty():
		return false
	_public_appearance = appearance
	return true


## 执行 `validate_map_presentation` 对应的模块操作。
## [param presentation] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func validate_map_presentation(presentation: Dictionary) -> Error:
	var kind := StringName(presentation.get("kind", CHARACTER_KIND))
	if kind == CHARACTER_KIND:
		return OK
	if kind != COMBAT_ACTOR_KIND:
		return ERR_INVALID_DATA
	var manifest_path := String(presentation.get("manifest", ""))
	if manifest_path != "res://assets/equipment_world/combat_visual_manifest.json":
		return ERR_INVALID_DATA
	var actor_id := StringName(presentation.get("actor_id", &""))
	var actors_value: Variant = _combat_manifest.get("actors", {})
	if actor_id == &"" or not actors_value is Dictionary:
		return ERR_INVALID_DATA
	return OK if (actors_value as Dictionary).has(String(actor_id)) else ERR_DOES_NOT_EXIST


## 执行 `apply_map_presentation` 对应的模块操作。
## [param presentation] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func apply_map_presentation(presentation: Dictionary) -> Error:
	var validation_error := validate_map_presentation(presentation)
	if validation_error != OK:
		return validation_error
	var kind := StringName(presentation.get("kind", CHARACTER_KIND))
	if kind == CHARACTER_KIND:
		presentation_kind = CHARACTER_KIND
		combat_actor_id = &""
		set_vehicle_destroyed(false)
		human_character.visible = true
		combat_presenter.visible = false
		combat_name_label.visible = false
		combat_status_bar.visible = false
		_apply_active_pose()
		return OK

	var requested_actor := _equipped_combat_actor_id
	if requested_actor == &"":
		requested_actor = StringName(presentation.get("actor_id", &""))
	if combat_presenter.current_actor_id != requested_actor:
		var present_error: Error = combat_presenter.present_actor(requested_actor)
		if present_error != OK:
			return present_error
	presentation_kind = COMBAT_ACTOR_KIND
	combat_actor_id = requested_actor
	human_character.visible = false
	combat_presenter.visible = true
	combat_name_label.visible = true
	combat_status_bar.visible = true
	_apply_active_pose()
	return OK


## 执行 `set_action` 对应的模块操作。
## [param action] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param direction] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_action(action: String, direction: int) -> void:
	var next_action := StringName(action)
	var next_direction := posmod(direction, 8)
	if _current_action == next_action and _current_direction == next_direction:
		return
	_current_action = next_action
	_current_direction = next_direction
	_apply_active_pose()


## 执行 `set_combat_layer_pose` 对应的模块操作。
## [param layer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param action] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param direction] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func set_combat_layer_pose(layer_id: StringName, action: StringName, direction: int) -> bool:
	if not is_combat_actor_active():
		return false
	return (
		combat_presenter.set_layer_action(layer_id, action)
		and combat_presenter.set_layer_direction(layer_id, direction)
	)


## 执行 `clear_combat_layer_action` 对应的模块操作。
## [param layer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func clear_combat_layer_action(layer_id: StringName) -> void:
	if combat_presenter != null:
		combat_presenter.clear_layer_action(layer_id)


## 用当前 PlayerVehicle 装配选择业务化战车 actor，替换地图中的新兵占位外观。
## [param vehicle] 当前玩家唯一的战车聚合对象。
## 返回清单中存在对应底盘 actor 且已完成切换时为 true。
## 设计：地图只决定“进入战车模式”，具体哪辆战车始终由当前玩家装配对象决定。
func apply_vehicle_equipment(vehicle: PlayerVehicle) -> bool:
	if vehicle == null or combat_presenter == null:
		return false
	var chassis := vehicle.loadout.at(0) as VehicleChassis
	var primary_weapon := vehicle.loadout.at(1)
	if chassis == null:
		combat_presenter.clear_actor()
		_equipped_combat_actor_id = &""
		_equipped_chassis_definition_id = ""
		_equipped_primary_definition_id = ""
		return false
	var primary_definition_id := primary_weapon.definition_id if primary_weapon != null else ""
	if chassis.definition_id == _equipped_chassis_definition_id \
			and primary_definition_id == _equipped_primary_definition_id \
			and combat_presenter.current_actor_id == &"equipped_combat_vehicle":
		return true
	var shadow_map: Dictionary = _combat_manifest.get("vehicle_shadow_component_by_chassis_definition", {})
	var components: Dictionary = _combat_manifest.get("components", {})
	var chassis_component := _equipment_component(chassis)
	var weapon_component := _equipment_component(primary_weapon)
	var shadow_component := String(shadow_map.get(chassis.definition_id, ""))
	if chassis_component.is_empty():
		combat_presenter.clear_actor()
		_equipped_combat_actor_id = &""
		_equipped_chassis_definition_id = ""
		_equipped_primary_definition_id = ""
		return false
	var layers: Array[Dictionary] = []
	if not shadow_component.is_empty() and components.has(shadow_component):
		layers.append(_vehicle_layer(
			&"shadow", -1, components[shadow_component], false
		))
	layers.append(_vehicle_layer(&"chassis", 0, chassis_component, true))
	if not weapon_component.is_empty():
		var primary_layer := _vehicle_layer(&"primary_weapon", 0, weapon_component, false)
		if primary_weapon is VehicleMiningArm:
			primary_layer["actions"]["collect"] = weapon_component["action"].duplicate(true)
		layers.append(primary_layer)
	var actor_id := &"equipped_combat_vehicle"
	var registered: Error = combat_presenter.register_actor(actor_id, {
		"display_name": chassis.display_name,
		"default_action": "idle",
		"layers": layers,
		"installed_components": [
			_combat_manifest.get("vehicle_component_by_equipment_definition", {}).get(chassis.definition_id, chassis.definition_id),
			_equipment_component_key(primary_weapon) if primary_weapon != null else ""],
	})
	if registered != OK:
		return false
	var presented: Error = combat_presenter.present_actor(actor_id)
	if presented != OK:
		return false
	_equipped_combat_actor_id = actor_id
	_equipped_chassis_definition_id = chassis.definition_id
	_equipped_primary_definition_id = primary_definition_id
	combat_actor_id = actor_id if presentation_kind == COMBAT_ACTOR_KIND else &""
	_apply_active_pose()
	return true


## 把单项业务组件动作扩展为战车 actor 的 idle、move 与可选 attack 动作。
## [param layer_id] shadow、chassis 或 primary_weapon。
## [param layer_z_index] 战车内部绘制层级。
## [param component] 运行时 components 中的业务组件定义。
## [param animated_while_moving] 是否在 move 时循环多帧底盘动画。
## 返回可直接登记到 CombatVisualPresenter 的图层定义。
func _vehicle_layer(
	layer_id: StringName,
	layer_z_index: int,
	component: Dictionary,
	animated_while_moving: bool,
) -> Dictionary:
	var source_action: Dictionary = component.get("action", {})
	var idle := source_action.duplicate(true)
	idle["fps"] = 0.0
	idle["loop"] = false
	if component.has("idle_action"):
		idle = component["idle_action"].duplicate(true)
	var move := source_action.duplicate(true)
	if not animated_while_moving:
		move["fps"] = 0.0
		move["loop"] = false
	var actions := {"idle": idle, "move": move}
	if layer_id != &"chassis":
		actions["attack"] = idle.duplicate(true)
	return {
		"id": String(layer_id),
		"z_index": layer_z_index,
		"actions": actions,
	}


## 从明确导入的组件或物品自身的荣耀世界图读取实际装备外观。
## [param equipment] 当前安装的战车装备。
## 返回本件装备的组件；缺失时返回空，不能保留上一件外观。
func _equipment_component(equipment: VehicleEquipment) -> Dictionary:
	if equipment == null:
		return {}
	var components: Dictionary = _combat_manifest.get("components", {})
	var key := _equipment_component_key(equipment)
	var component: Dictionary = components.get(key, {})
	return component if not component.is_empty() else CombatAnimationLibrary.equipment_component(equipment)


## 将实际装备映射到统一战车表现组件键。
## [param equipment] 当前安装的战车装备。
## 返回 manifest 中稳定的组件标识。
func _equipment_component_key(equipment: VehicleEquipment) -> String:
	var components: Dictionary = _combat_manifest.get("components", {})
	var key := String(_combat_manifest.get("vehicle_component_by_equipment_definition", {}).get(equipment.definition_id, equipment.definition_id))
	if equipment is VehicleMiningArm:
		var mining_level := equipment.required_skill_level
		if mining_level <= 0:
			mining_level = {
				"glory_equipment_collector_ac947ee094": 10,
				"glory_equipment_collector2_21f80f2164": 30,
				"glory_equipment_collector3_87154ee651": 60,
				"glory_equipment_collector4_62b573e9d7": 100,
				"glory_equipment_collector5_840acf4362": 150,
				"glory_equipment_collector6_ac4d3e4b7b": 200,
				"glory_equipment_collector7_76bbb2cfae": 250,
			}.get(equipment.definition_id, 0)
		var mining_key := "mining_arm_level_%d" % mining_level
		if components.has(mining_key):
			return mining_key
	return key


## 执行 `set_combat_status` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_combat_status(snapshot: Dictionary) -> void:
	if combat_status_bar == null or snapshot.is_empty():
		return
	combat_status_bar.set_health(float(snapshot.get("health", 0)), float(snapshot.get("max_health", 1)))
	combat_status_bar.set_energy(
		float(snapshot.get("working_energy", 0.0)),
		float(snapshot.get("working_energy_capacity", 1.0)),
	)


## 设置人形动画倍率；战车继续采用其荣耀来源清单中的独立帧率。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_animation_speed_scale(value: float) -> void:
	_animation_speed_scale = maxf(value, 0.0)
	if human_character != null:
		human_character.set_animation_speed_scale(_animation_speed_scale)


## 让世界人物服装层消费当前 Player 的固定人物装备对象。
## [param equipment] 当前玩家的 CharacterEquipment。
## [param character_catalog] 已导入的语义化人物动画目录。
## 返回服装表现是否成功应用。
func apply_character_equipment(
	equipment: CharacterEquipment,
	character_catalog: Dictionary,
) -> bool:
	if human_character == null or equipment == null:
		return false
	var upper_body := equipment.at("upper_body")
	if upper_body == null:
		human_character.set_equipment_visible(false)
		_clothing_appearance_key = ""
		return true
	var world_presentation := upper_body.presentation_for("world")
	var appearance_key := String(world_presentation.get("world_equipment_key", ""))
	if appearance_key.is_empty() or not character_catalog.has(appearance_key):
		push_warning("Character clothing has no world appearance: %s" % upper_body.definition_id)
		return false
	if appearance_key == _clothing_appearance_key and human_character.equipment.visible:
		return true
	var character_set := CharacterFactoryScript.build_character_set(
		character_catalog, appearance_key, _character_sex
	)
	human_character.set_equipment_set(character_set)
	_clothing_appearance_key = appearance_key
	return true


## 权威角色性别变化时切换人形裸模及阴影。
func apply_character_sex(sex: String, character_catalog: Dictionary) -> void:
	if sex == _character_sex or human_character == null:
		return
	human_character.set_body_set(CharacterFactoryScript.build_body_set(character_catalog, sex))
	_character_sex = sex


## 按荣耀版死亡表现降低战车本体透明度；名称和状态条保持可读。
## [param destroyed] 调用方传入的 `destroyed` 参数。
func set_vehicle_destroyed(destroyed: bool) -> void:
	_vehicle_destroyed = destroyed
	if combat_presenter != null:
		combat_presenter.modulate.a = 0.5 if destroyed else 1.0


## 报告当前地图是否正在使用战斗载具外观。
## 返回该函数计算、查询或操作得到的结果。
func is_combat_actor_active() -> bool:
	return (
		presentation_kind == COMBAT_ACTOR_KIND
		and combat_presenter != null
		and combat_presenter.current_actor_id != &""
	)


## 每帧只推进当前可见的战斗角色动画。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _process(delta: float) -> void:
	if presentation_kind == COMBAT_ACTOR_KIND and combat_presenter != null:
		combat_presenter.advance(delta)


## 将已缓存动作与朝向同步到当前可见表现。
## 设计：相同动作不重置时间；客户端每帧同步待机姿态时，装备的采矿循环仍需继续推进。
func _apply_active_pose() -> void:
	if presentation_kind == CHARACTER_KIND:
		if human_character != null:
			human_character.set_action(_human_action(_current_action), _current_direction)
		return
	if combat_presenter == null or combat_presenter.current_actor_id == &"":
		return
	combat_presenter.set_direction(_current_direction)
	var desired_action := _combat_action(_current_action)
	if combat_presenter.current_action_id != desired_action:
		combat_presenter.set_action(desired_action)


## 执行 `human_action` 对应的模块操作。
## [param action] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _human_action(action: StringName) -> String:
	return "move" if action in [&"move", &"moving", &"walk", &"walking", &"run", &"running"] else "stand"


## 执行 `combat_action` 对应的模块操作。
## [param action] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _combat_action(action: StringName) -> StringName:
	if action in [&"move", &"moving", &"walk", &"walking", &"run", &"running"]:
		return &"move"
	if action == &"attack":
		return &"attack"
	return &"idle"


## 创建战车模式独立名称标签，使隐藏人形时玩家身份仍然可见。
## [param display_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param name_color] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _build_name_label(display_name: String, name_color: Color) -> Label:
	var label := Label.new()
	label.name = "CombatNameLabel"
	label.text = display_name
	label.position = COMBAT_NAME_LABEL_POSITION
	label.size = Vector2(130, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", name_color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
