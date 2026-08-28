extends SceneTree

const PresenterScript := preload(
	"res://scripts/client/presentation/combat/combat_visual_presenter.gd"
)
const RUNTIME_MANIFEST := "res://assets/equipment_world/combat_visual_manifest.json"
const SOURCE_MANIFEST := "res://assets/equipment_world/source_manifest.json"

var assertions := 0
var failures: Array[String] = []


## 延迟执行需要资源导入与节点树生命周期的战斗表现冒烟测试。
func _init() -> void:
	call_deferred("_run")


## 验证业务清单、荣耀来源审计、八方向切换、动作推进和四类怪物加载。
## 设计：测试只加载按需资源，不实例化大厅、网络或服务端逻辑。
func _run() -> void:
	var runtime := _read_json(RUNTIME_MANIFEST)
	var source := _read_json(SOURCE_MANIFEST)
	_expect_equal(int(runtime.get("schema_version", 0)), 2, "runtime schema is versioned")
	_expect_equal((runtime.get("direction_order", []) as Array).size(), 8, "runtime declares eight directions")
	_expect_equal((source.get("assets", []) as Array).size(), 6, "starter components, shadow and cannon effects are audited")
	_expect_equal(String(source.get("source_version", "")), "starhome_lz_ry", "Glory is canonical source")
	var components: Dictionary = runtime.get("components", {})
	_expect_equal(String((components["beginner_engine"] as Dictionary).get("render_policy", "")), "installed_only", "engine is configured but not drawn")
	_expect_runtime_names_are_semantic(runtime)
	_expect_source_components(source)
	_expect_all_resources_load(runtime)

	var presenter = PresenterScript.new()
	root.add_child(presenter)
	_expect_equal(presenter.configure(runtime), OK, "presenter accepts runtime manifest")
	_expect_equal(presenter.present_actor(&"starter_combat_vehicle"), OK, "starter vehicle presents")
	_expect_equal(presenter.layer_frame(&"chassis"), 0, "vehicle starts east at first chassis frame")
	_expect_equal(presenter.layer_frame(&"primary_weapon"), 0, "vehicle starts east at first weapon frame")
	presenter.set_direction(7)
	_expect_equal(presenter.layer_frame(&"chassis"), 28, "chassis selects south-east direction block")
	_expect_equal(presenter.layer_frame(&"primary_weapon"), 7, "weapon selects south-east frame")
	_expect_true(presenter.set_action(&"move"), "vehicle supports move")
	presenter.advance(0.21)
	_expect_equal(presenter.layer_frame(&"chassis"), 30, "chassis advances inside selected direction")
	_expect_equal(presenter.layer_frame(&"primary_weapon"), 7, "one-frame weapon remains stable")
	_expect_true(presenter.set_layer_direction(&"primary_weapon", 2), "weapon accepts independent aim direction")
	_expect_equal(presenter.layer_frame(&"chassis"), 30, "independent aiming does not rotate chassis")
	_expect_equal(presenter.layer_frame(&"primary_weapon"), 2, "independent aiming rotates only weapon")
	_expect_true(presenter.set_action(&"attack"), "weapon exposes attack action")
	_expect_equal(presenter.layer_frame(&"chassis"), 28, "missing chassis attack falls back to idle")

	_expect_monster(presenter, &"om_adult_standard", {&"idle": 5, &"move": 5, &"attack": 6})
	_expect_monster(presenter, &"om_larva_standard", {&"idle": 5, &"move": 5, &"attack": 5})
	_expect_shared_monster(presenter, &"photosensitive_orb_standard", [&"idle", &"move", &"attack"])
	_expect_shared_monster(presenter, &"photosensitive_orb_cold", [&"idle", &"move", &"attack"])
	_expect_shared_monster(presenter, &"photosensitive_orb_malignant", [&"idle", &"move", &"attack"])
	_expect_shared_monster(presenter, &"toxic_gel_standard", [&"idle", &"attack"])
	_expect_monster(presenter, &"toxic_gel_standard", {&"move": 5})
	_expect_true(presenter.set_action(&"attack"), "toxic gel uses its source-confirmed idle body during projectile attack")

	presenter.queue_free()
	_finish()


## 执行 `read_json` 对应的模块操作。
## [param path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _read_json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if value is Dictionary:
		return value
	failures.append("JSON root is not a dictionary: %s" % path)
	return {}


## 执行 `expect_runtime_names_are_semantic` 对应的模块操作。
## [param manifest] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_runtime_names_are_semantic(manifest: Dictionary) -> void:
	var expression := RegEx.new()
	expression.compile("(?i)(pic2?|\\.ale|CHN_[0-9]{4}|[0-9]{4}_[0-9]{2}_[0-9]{2})")
	var serialized := JSON.stringify(manifest)
	_expect_true(expression.search(serialized) == null, "runtime manifest contains business names only")


## 执行 `expect_source_components` 对应的模块操作。
## [param source] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_source_components(source: Dictionary) -> void:
	var by_id: Dictionary = {}
	for entry_value: Variant in source.get("assets", []):
		var entry: Dictionary = entry_value
		by_id[String(entry.get("asset_id", ""))] = entry
	_expect_equal(int((by_id["recruit_tank"] as Dictionary).get("frame_count", 0)), 32, "chassis has 8x4 frames")
	_expect_equal(int((by_id["recruit_tank_shadow"] as Dictionary).get("frame_count", 0)), 8, "chassis shadow has eight directions")
	_expect_equal(int((by_id["recruit_energy_cannon"] as Dictionary).get("frame_count", 0)), 8, "cannon has eight frames")
	var engine: Dictionary = by_id["beginner_engine"]
	_expect_equal(int(engine.get("frame_count", 0)), 1, "engine source is a shared single frame")
	_expect_equal(String(engine.get("direction_mode", "")), "shared", "engine does not invent directions")
	_expect_true(not bool(engine.get("world_visible", true)), "engine is not a world composite layer")
	_expect_equal(
		int((by_id["recruit_energy_cannon_projectile"] as Dictionary).get("frame_count", 0)),
		1,
		"starter cannon projectile is a single-frame effect",
	)
	_expect_equal(
		int((by_id["recruit_energy_cannon_impact_candidate"] as Dictionary).get("frame_count", 0)),
		8,
		"starter cannon impact candidate has eight frames",
	)
	for entry_value: Variant in by_id.values():
		var entry: Dictionary = entry_value
		_expect_equal(String(entry.get("source_sha256", "")).length(), 64, "raw source SHA-256 is retained")


## 执行 `expect_all_resources_load` 对应的模块操作。
## [param manifest] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_all_resources_load(manifest: Dictionary) -> void:
	var components: Dictionary = manifest.get("components", {})
	for component_value: Variant in components.values():
		var component: Dictionary = component_value
		_expect_action_resource_load(component.get("action", {}))
	var weapons: Dictionary = manifest.get("weapons", {})
	for weapon_value: Variant in weapons.values():
		var weapon: Dictionary = weapon_value
		_expect_action_resource_load(weapon.get("projectile", {}))
		_expect_action_resource_load(weapon.get("impact", {}))
	var actors: Dictionary = manifest.get("actors", {})
	for actor_value: Variant in actors.values():
		var actor: Dictionary = actor_value
		for layer_value: Variant in actor.get("layers", []):
			var layer: Dictionary = layer_value
			var actions: Dictionary = layer.get("actions", {})
			for action_value: Variant in actions.values():
				_expect_action_resource_load(action_value)
	var monster_effects: Dictionary = manifest.get("monster_effects", {})
	_expect_equal(monster_effects.size(), 6, "all imported first-wave monster variants map a death effect")
	for effect_set_value: Variant in monster_effects.values():
		var effect_set: Dictionary = effect_set_value
		_expect_action_resource_load(effect_set.get("death", {}))


## 执行 `expect_action_resource_load` 对应的模块操作。
## [param action_value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_action_resource_load(action_value: Variant) -> void:
	if not action_value is Dictionary:
		_expect_true(false, "action descriptor is a dictionary")
		return
	var action: Dictionary = action_value
	var resource_path := String(action.get("resource", ""))
	var frames := ResourceLoader.load(resource_path, "SpriteFrames") as SpriteFrames
	_expect_true(frames != null, "SpriteFrames loads: %s" % resource_path)
	if frames != null:
		_expect_true(frames.has_animation(&"raw"), "resource exposes raw animation")


## 执行 `expect_monster` 对应的模块操作。
## [param presenter] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param actor_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param action_frames] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_monster(
	presenter: Node2D,
	actor_id: StringName,
	action_frames: Dictionary,
) -> void:
	_expect_equal(presenter.present_actor(actor_id), OK, "%s presents" % actor_id)
	for action_id_value: Variant in action_frames.keys():
		var action_id := StringName(action_id_value)
		var frames_per_direction := int(action_frames[action_id_value])
		_expect_true(presenter.set_action(action_id), "%s supports %s" % [actor_id, action_id])
		presenter.set_direction(6)
		_expect_equal(
			presenter.layer_frame(&"body"),
			6 * frames_per_direction,
			"%s %s selects south block" % [actor_id, action_id],
		)


## 执行 `expect_shared_monster` 对应的模块操作。
## [param presenter] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param actor_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param actions] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_shared_monster(
	presenter: Node2D,
	actor_id: StringName,
	actions: Array[StringName],
) -> void:
	_expect_equal(presenter.present_actor(actor_id), OK, "%s presents" % actor_id)
	for action_id in actions:
		_expect_true(presenter.set_action(action_id), "%s supports %s" % [actor_id, action_id])
		presenter.set_direction(0)
		var east_frame: int = presenter.layer_frame(&"body")
		presenter.set_direction(7)
		_expect_equal(presenter.layer_frame(&"body"), east_frame, "%s shares direction frames" % actor_id)


## 执行 `expect_true` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_true(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures.append(label)


## 执行 `expect_equal` 对应的模块操作。
## [param actual] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param expected] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [label, actual, expected])


## 输出测试汇总，并依据累计失败数量设置进程退出码。
func _finish() -> void:
	if failures.is_empty():
		print("COMBAT VISUAL PRESENTER TESTS PASSED: %d assertions" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("COMBAT VISUAL PRESENTER TESTS FAILED: %d assertions, %d failures" % [assertions, failures.size()])
	quit(1)
