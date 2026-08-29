extends SceneTree

const ControllerScript := preload(
	"res://scripts/client/presentation/combat/ground_loot_world_controller.gd"
)
const ItemCatalogScript := preload("res://scripts/domain/items/item_catalog.gd")

var assertions := 0
var failures: Array[String] = []


## 延迟执行依赖场景树和纹理资源的地面掉落表现测试。
func _init() -> void:
	call_deferred("_run")


## 验证荣耀原尺寸、ALE 原点命中、快照更新及已拾取清理。
func _run() -> void:
	var catalog: ItemCatalog = ItemCatalogScript.new()
	var initialized := catalog.initialize()
	_expect(initialized.is_ok, "shared item catalog should parse")
	if not initialized.is_ok:
		_finish()
		return
	var world := Node2D.new()
	world.name = "LootWorld"
	world.y_sort_enabled = true
	root.add_child(world)
	var controller = ControllerScript.new()
	root.add_child(controller)
	_expect(
		controller.configure(world, catalog) == OK,
		"ground loot controller should configure",
	)
	controller.apply_snapshot(_snapshot([_loot(
		"loot.biosilicon.1", "low_grade_biosilicon", 2, Vector2(100.0, 200.0)
	)]))
	_expect(controller.active_view_count() == 1, "snapshot should create one loot view")
	var view = controller.view_for_loot("loot.biosilicon.1")
	_expect(view != null, "loot view should be indexed by authoritative loot id")
	if view != null:
		_expect(
			view.item is GameItem and view.item.instance_id == "loot.biosilicon.1",
			"ground presentation should retain a domain item with the authoritative identity",
		)
		_expect(
			view.local_hit_rect() == Rect2(-34.0, -26.0, 50.0, 42.0),
			"biosilicon should retain the original 50x42 frame and ALE origin",
		)
		_expect(
			controller.loot_at(Vector2(67.0, 175.0)) == "loot.biosilicon.1",
			"click inside the original frame rectangle should select the loot",
		)
		_expect(
			controller.loot_at(Vector2(65.0, 175.0)).is_empty(),
			"click outside the original frame rectangle should not select the loot",
		)
		view.set_hovered(true)
		_expect(
			view.is_hover_glow_enabled(),
			"hover should enable the original-client texture glow",
		)
		_expect(
			is_equal_approx(view.hover_glow_radius(), 4.0),
			"ground loot glow should retain the original four-pixel radius",
		)
		_expect(
			view.get_node_or_null("HoverBackground") == null,
			"ground loot should not create the former rectangular hover background",
		)
		view.set_hovered(false)
		_expect(
			not view.is_hover_glow_enabled(),
			"leaving loot should disable the glow without tinting the source icon",
		)
	controller.apply_snapshot(_snapshot([_loot(
		"loot.biosilicon.1", "low_grade_biosilicon", 3, Vector2(140.0, 220.0)
	)]))
	view = controller.view_for_loot("loot.biosilicon.1")
	_expect(
		view != null and view.position == Vector2(140.0, 220.0) and view.quantity == 3,
		"later snapshots should update the same view position and quantity",
	)
	controller.apply_snapshot(_snapshot([]))
	_expect(controller.active_view_count() == 0, "missing authoritative loot should remove its view")
	controller.queue_free()
	world.queue_free()
	_finish()


## 构造只含地面掉落的最小战斗快照。
## [param loot] 当前地图可见掉落 DTO 数组。
## 返回控制器可消费的权威快照。
func _snapshot(loot: Array) -> Dictionary:
	return {"server_tick": 1, "ground_loot": loot}


## 构造一个权威地面掉落 DTO。
## [param loot_id] 掉落实例标识。
## [param definition_id] 物品业务定义标识。
## [param quantity] 堆叠数量。
## [param position] 世界脚点。
## 返回可进入快照的字典。
func _loot(loot_id: String, definition_id: String, quantity: int, position: Vector2) -> Dictionary:
	return {
		"loot_id": loot_id,
		"item_definition_id": definition_id,
		"quantity": quantity,
		"position": [position.x, position.y],
	}


## 记录一个布尔断言。
## [param condition] 期望条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出测试汇总并以失败数量设置退出码。
func _finish() -> void:
	if failures.is_empty():
		print("GROUND_LOOT_WORLD_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("GROUND_LOOT_WORLD_FAILED (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
