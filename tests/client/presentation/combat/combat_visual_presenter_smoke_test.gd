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
## Design: 测试只加载按需资源，不实例化大厅、网络或服务端逻辑。
func _run() -> void:
	var runtime := _read_json(RUNTIME_MANIFEST)
	var source := _read_json(SOURCE_MANIFEST)
	_expect_equal(int(runtime.get("schema_version", 0)), 1, "runtime schema is versioned")
	_expect_equal((runtime.get("direction_order", []) as Array).size(), 8, "runtime declares eight directions")
	_expect_equal((source.get("assets", []) as Array).size(), 3, "three starter components are audited")
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
	_expect_true(presenter.set_action(&"attack"), "weapon exposes attack action")
	_expect_equal(presenter.layer_frame(&"chassis"), 28, "missing chassis attack falls back to idle")

	_expect_monster(presenter, &"om_adult_standard", {&"idle": 5, &"move": 5, &"attack": 6})
	_expect_monster(presenter, &"om_larva_standard", {&"idle": 5, &"move": 5, &"attack": 5})
	_expect_shared_monster(presenter, &"photosensitive_orb_standard", [&"idle", &"move", &"attack"])
	_expect_shared_monster(presenter, &"toxic_gel_standard", [&"idle"])
	_expect_monster(presenter, &"toxic_gel_standard", {&"move": 5})
	_expect_true(not presenter.set_action(&"attack"), "toxic gel rejects undeclared attack")

	presenter.queue_free()
	_finish()


## 读取 [param path] 的 JSON 对象。
## Returns JSON 根为字典时返回其内容，否则记录失败并返回空字典。
func _read_json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if value is Dictionary:
		return value
	failures.append("JSON root is not a dictionary: %s" % path)
	return {}


## 断言运行时 [param manifest] 不泄漏旧目录、ALE 容器或时间戳标识。
func _expect_runtime_names_are_semantic(manifest: Dictionary) -> void:
	var expression := RegEx.new()
	expression.compile("(?i)(pic2?|\\.ale|CHN_[0-9]{4}|[0-9]{4}_[0-9]{2}_[0-9]{2})")
	var serialized := JSON.stringify(manifest)
	_expect_true(expression.search(serialized) == null, "runtime manifest contains business names only")


## 验证 [param source] 中三个装备部件的帧数、方向策略与世界可见性证据。
func _expect_source_components(source: Dictionary) -> void:
	var by_id: Dictionary = {}
	for entry_value: Variant in source.get("assets", []):
		var entry: Dictionary = entry_value
		by_id[String(entry.get("asset_id", ""))] = entry
	_expect_equal(int((by_id["recruit_tank"] as Dictionary).get("frame_count", 0)), 32, "chassis has 8x4 frames")
	_expect_equal(int((by_id["recruit_energy_cannon"] as Dictionary).get("frame_count", 0)), 8, "cannon has eight frames")
	var engine: Dictionary = by_id["beginner_engine"]
	_expect_equal(int(engine.get("frame_count", 0)), 1, "engine source is a shared single frame")
	_expect_equal(String(engine.get("direction_mode", "")), "shared", "engine does not invent directions")
	_expect_true(not bool(engine.get("world_visible", true)), "engine is not a world composite layer")
	for entry_value: Variant in by_id.values():
		var entry: Dictionary = entry_value
		_expect_equal(String(entry.get("source_sha256", "")).length(), 64, "raw source SHA-256 is retained")


## 递归加载 [param manifest] 中所有动作资源，防止清单路径漂移。
func _expect_all_resources_load(manifest: Dictionary) -> void:
	var components: Dictionary = manifest.get("components", {})
	for component_value: Variant in components.values():
		var component: Dictionary = component_value
		_expect_action_resource_load(component.get("action", {}))
	var actors: Dictionary = manifest.get("actors", {})
	for actor_value: Variant in actors.values():
		var actor: Dictionary = actor_value
		for layer_value: Variant in actor.get("layers", []):
			var layer: Dictionary = layer_value
			var actions: Dictionary = layer.get("actions", {})
			for action_value: Variant in actions.values():
				_expect_action_resource_load(action_value)


## 加载 [param action_value] 指向的 SpriteFrames，并验证统一的原始动画入口。
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


## 通过 [param presenter] 验证八向怪物 [param actor_id] 支持 [param action_frames] 声明的动作与方向块宽。
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


## 通过 [param presenter] 验证无朝向怪物 [param actor_id] 的 [param actions] 在八个朝向上复用同一帧块。
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


## 统计 [param value] 布尔断言，并以 [param label] 记录失败上下文。
func _expect_true(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures.append(label)


## 断言 [param actual] 与 [param expected] 相等，并用 [param label] 记录上下文。
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
