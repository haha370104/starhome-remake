extends SceneTree

const MonsterWorldControllerScript := preload(
	"res://scripts/client/presentation/combat/monster_world_controller.gd"
)
const MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"

var assertions := 0
var failures: Array[String] = []


## 延迟执行依赖场景树生命周期的怪物悬浮名称测试。
func _init() -> void:
	call_deferred("_run")


## 验证红色名称默认隐藏、仅显示一个悬浮目标并紧邻血条上方。
func _run() -> void:
	var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_expect(manifest_value is Dictionary, "战斗表现清单必须可解析")
	if not manifest_value is Dictionary:
		_finish()
		return
	var world := Node2D.new()
	root.add_child(world)
	var local_player := Node2D.new()
	world.add_child(local_player)
	var controller = MonsterWorldControllerScript.new()
	root.add_child(controller)
	_expect(controller.configure(world, manifest_value, local_player) == OK, "怪物控制器必须配置成功")
	controller.apply_snapshot(_snapshot())
	var first = world.get_node_or_null("Monster_monster_first")
	var second = world.get_node_or_null("Monster_monster_second")
	_expect(first != null and second != null, "两个怪物视图都必须生成")
	if first != null and second != null:
		var shared_font: Font = first.name_label.get_theme_font("font")
		_expect(shared_font == second.name_label.get_theme_font("font"),
			"同屏怪物必须复用名称字体，避免每次补怪重新加载系统字体")
		_expect(not first.name_label.visible and not second.name_label.visible, "怪物名称默认必须隐藏")
		_expect(
			first.name_label.get_theme_color("font_color") == Color.RED,
			"怪物名称必须使用原客户端红色",
		)
		_expect(
			first.name_label.get_theme_font_size("font_size") == first.NAME_FONT_SIZE,
			"怪物名称必须使用旧客户端比例的小字号",
		)
		_expect(
			first.health_bar.position == first.HEALTH_BAR_OFFSET,
			"血条组合必须下移至怪物脚点之外",
		)
		_expect(
			first.name_label.position.y + first.name_label.size.y < first.health_bar.position.y,
			"怪物名称必须位于血条正上方",
		)
		_expect(
			is_equal_approx(
				first.health_bar.position.y
					- (first.name_label.position.y + first.name_label.size.y),
				1.0,
			),
			"怪物名称与血条整体下移后仍保持 1px 间距",
		)
		_expect(first.health_bar._bar_width == 60.0,
			"怪物血条应从 50px 增加 20% 至 60px")
		_expect(first.health_bar.position.x == 0.0,
			"血条以怪物脚点为水平中心，左右各延伸 30px")
		_expect(
			is_equal_approx(
				first.name_label.position.x + first.name_label.size.x * 0.5,
				first.health_bar.position.x,
			),
			"怪物名称与血条必须沿同一水平中心线对齐",
		)
		_expect(
			(first.name_label.get_theme_font("font") as SystemFont).font_weight == 700,
			"怪物名称使用微软雅黑粗体提高辨识度",
		)
		_expect(first.name_label.get_theme_constant("outline_size") == 2, "名称使用黑色轮廓隔离地图背景")
		_expect(first.health_bar.position.y == 25.0, "名称和血条从原20px基线整体下移5px")
		var first_hover_point: Vector2 = first.position + first.visual_collision_offset
		_expect(controller.update_hover_at(first_hover_point) == "monster.first", "应命中第一个怪物")
		_expect(first.name_label.visible and not second.name_label.visible, "只显示第一个悬浮名称")
		if "--capture" in OS.get_cmdline_user_args():
			print("MONSTER_NAME_FONT: ", first.name_label.get_theme_font("font").get_font_name())
			controller.set_process(false)
			var backdrop := ColorRect.new()
			backdrop.color = Color("827b60")
			backdrop.size = Vector2(420, 320)
			backdrop.z_index = -1
			world.add_child(backdrop)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/monster-name-weight.png")
		var second_hover_point: Vector2 = second.position + second.visual_collision_offset
		_expect(controller.update_hover_at(second_hover_point) == "monster.second", "应切换至第二个怪物")
		_expect(not first.name_label.visible and second.name_label.visible, "切换时必须隐藏旧名称")
		_expect(controller.update_hover_at(Vector2(-1000.0, -1000.0)).is_empty(), "离开怪物后应无目标")
		_expect(not first.name_label.visible and not second.name_label.visible, "离开后名称必须隐藏")
		controller.clear()
		await process_frame
		controller.apply_snapshot(_snapshot())
		var respawned = world.get_node_or_null("Monster_monster_first")
		_expect(respawned != null and respawned.name_label.get_theme_font("font") == shared_font,
			"旧怪物释放后再次补怪仍应复用名称字体")
	controller.clear()
	controller.queue_free()
	world.queue_free()
	_finish()


## 构造包含两个相邻怪物的权威快照。
## 返回可供怪物表现层消费的测试快照。
func _snapshot() -> Dictionary:
	return {
		"server_tick": 1,
		"local_entity_id": "player.local",
		"monsters": [
			_monster("monster.first", "奥姆虫", Vector2(140.0, 220.0)),
			_monster("monster.second", "毒性奥姆虫", Vector2(260.0, 220.0)),
		],
		"recent_events": [],
	}


## 构造单个存活怪物的表现快照。
## [param entity_id] 怪物实体 ID。
## [param display_name] 怪物显示名称。
## [param position] 怪物脚点世界坐标。
## 返回单个怪物快照字典。
func _monster(entity_id: String, display_name: String, position: Vector2) -> Dictionary:
	return {
		"entity_id": entity_id,
		"species_id": "om_adult",
		"display_name": display_name,
		"combat_actor_id": "om_adult_standard",
		"position": [position.x, position.y],
		"health": 60,
		"max_health": 60,
		"alive": true,
		"action": "idle",
		"facing_index": 0,
	}


## 记录一条布尔断言。
## [param condition] 断言条件。
## [param message] 条件失败时输出的说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 输出测试结果并结束进程。
func _finish() -> void:
	if failures.is_empty():
		print("MONSTER_HOVER_NAME_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MONSTER_HOVER_NAME_FAILED (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
