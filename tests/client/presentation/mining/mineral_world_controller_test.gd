extends SceneTree

const ControllerScript := preload(
	"res://scripts/client/presentation/mining/mineral_world_controller.gd"
)
const MANIFEST_PATH := "res://assets/minerals/mining_asset_manifest.json"

var assertions := 0
var failures: Array[String] = []


## 初始化对象及其运行时依赖。
func _init() -> void:
	call_deferred("_run")


## 验证荣耀矿源帧、脚点命中、储量更新和权威删除投影。
func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_expect(parsed is Dictionary, "mining asset manifest should parse")
	if not parsed is Dictionary:
		_finish()
		return
	var world := Node2D.new()
	world.y_sort_enabled = true
	root.add_child(world)
	var controller = ControllerScript.new()
	root.add_child(controller)
	_expect(controller.configure(world, parsed) == OK, "mineral controller should configure")
	controller.apply_snapshot(_snapshot([
		_source("field.mine.1", "iron_ore", Vector2(100.0, 200.0), 3, 50),
		_source("field.mine.2", "graphite_ore", Vector2(300.0, 400.0), 6, 50),
	]))
	_expect(controller.active_view_count() == 2, "snapshot should create two mineral views")
	var iron = controller.view_for_source("field.mine.1")
	_expect(iron != null, "iron source should be indexed by authoritative id")
	if iron != null:
		_expect(iron.displayed_variant() == 3, "source variant should select the ALE atlas frame")
		_expect(
			iron.local_hit_rect() == Rect2(-65.0, -80.0, 138.0, 138.0),
			"mine should retain the original ALE bounds and origin",
		)
		_expect(
			controller.source_at(Vector2(100.0, 200.0)) == "field.mine.1",
			"a click on the source footpoint should select it",
		)
		_expect(
			controller.source_position("field.mine.1") == Vector2(100.0, 200.0),
			"selection should resolve the authoritative source position",
		)
	controller.apply_snapshot(_snapshot([
		_source("field.mine.1", "iron_ore", Vector2(100.0, 200.0), 3, 49),
	]))
	iron = controller.view_for_source("field.mine.1")
	_expect(
		iron != null and iron.remaining == 49 and iron.displayed_variant() == 3,
		"collection should update remaining content without changing appearance",
	)
	_expect(controller.active_view_count() == 1, "missing source should remove its stale view")
	controller.apply_snapshot(_snapshot([]))
	_expect(controller.active_view_count() == 0, "depleted source should disappear on snapshot")
	var all_sources: Array = []
	var sequence := 0
	for mineral_id: String in parsed.get("definitions", {}):
		var definition: Dictionary = parsed["definitions"][mineral_id]
		if not definition.has("world_animation"):
			continue
		all_sources.append({
			"source_id": "catalog.mine.%d" % sequence,
			"mineral_id": mineral_id,
			"display_name": mineral_id,
			"position": [float(sequence * 200), 0.0],
			"remaining": 50,
			"required_mining_level": 0,
			"visual_variant": 0,
		})
		sequence += 1
	controller.apply_snapshot(_snapshot(all_sources))
	_expect(controller.active_view_count() == 27, "24 类原有矿源及硫磷钾三种矿石世界视图应可渲染")
	controller.queue_free()
	world.queue_free()
	_finish()


## 构建 `snapshot` 对应的只读状态快照。
## [param sources] 调用方传入的 `sources` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _snapshot(sources: Array) -> Dictionary:
	return {"server_tick": 1, "mine_sources": sources}


## 执行 `source` 对应的模块操作。
## [param source_id] 调用方传入的 `source_id` 参数。
## [param mineral_id] 调用方传入的 `mineral_id` 参数。
## [param position] 调用方传入的 `position` 参数。
## [param variant] 调用方传入的 `variant` 参数。
## [param remaining] 调用方传入的 `remaining` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _source(
	source_id: String,
	mineral_id: String,
	position: Vector2,
	variant: int,
	remaining: int,
) -> Dictionary:
	var names := {
		"iron_ore": "铁矿",
		"silicon_ore": "硅矿",
		"graphite_ore": "石墨矿",
	}
	return {
		"source_id": source_id,
		"mineral_id": mineral_id,
		"display_name": names[mineral_id],
		"position": [position.x, position.y],
		"remaining": remaining,
		"capacity": 50,
		"required_mining_level": 10,
		"visual_variant": variant,
		"alpha": 0.9,
	}


## 记录一项测试断言及其失败信息。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 汇总测试断言并以对应退出码结束测试。
func _finish() -> void:
	if failures.is_empty():
		print("MINERAL_WORLD_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MINERAL_WORLD_FAILED (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
