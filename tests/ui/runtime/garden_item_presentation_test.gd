extends SceneTree

const ITEMS := {
	"item:material:c87ab4c9ebec": ["小椰子", "清甜可口"],
	"item:material:2990ca709816": ["生豆", "可以提炼出食用油"],
	"item:material:bf7cb63cd4fa": ["植物棉", "提炼纤维纺织线"],
	"item:material:6116d8b965c6": ["面瓜", "可以磨成面粉"],
	"item:material:212589b5bafd": ["糖瓜", "果肉能分泌象蜜一样甜的汁液"],
}
var checks := 0
var failures: Array[String] = []


## 用真实目录、原图和背包视图检查果实大小及原版说明，支持GPU截图。
func _initialize() -> void:
	call_deferred("_run")


## 验证裁切不丢像素、旧物品身份不变、五类说明显示，以及非采摘物品保持原图范围。
func _run() -> void:
	root.size = Vector2i(720, 570)
	var catalog := ItemCatalog.new()
	_check(catalog.initialize().is_ok, "物品目录可加载")
	var carried: Array[GameItem] = []
	for id: String in ITEMS:
		var slot := carried.size()
		var created := catalog.create(id, {"instance_id": "old-garden-%d" % slot, "quantity": 7,
			"position_px": [slot * 55, 37], "footprint_px": [30, 30]})
		_check(created.is_ok, "旧采摘物品按原ID加载")
		if not created.is_ok: continue
		var item: GameItem = created.value
		carried.append(item)
		_check(item.display_name == ITEMS[id][0] and item.description.contains(ITEMS[id][1]) \
			and not item.description.contains("掉落证据"), "使用原版名称与说明：" + item.display_name)
		var visual := item.presentation_for("inventory")
		var resolved := ItemPresentationTextureResolver.resolve(visual)
		var full := visual.duplicate(true)
		full.erase("source_rect")
		var original := ItemPresentationTextureResolver.resolve(full)
		var frame_image: Image = original.texture.get_image()
		var image: Image = resolved.texture.get_image()
		_check(frame_image.get_region(frame_image.get_used_rect()).get_data() == image.get_data(),
			"有效像素完整保留，仅去透明留白：" + item.display_name)
		_check(image.get_used_rect() == Rect2i(Vector2i.ZERO, image.get_size()), "裁切后没有外围空白")
		_check(resolved.texture is AtlasTexture and resolved.texture.filter_clip, "图集区域独立且启用边缘保护")
		var invalid := visual.duplicate(true)
		invalid.source_rect = [0, 0, 9999, 9999]
		_check(ItemPresentationTextureResolver.resolve(invalid).is_empty(), "越界裁切不采样相邻帧")
	var engine: GameItem = catalog.create("beginner_engine", {"instance_id": "unchanged-engine"}).value
	var engine_texture := ItemPresentationTextureResolver.resolve(engine.presentation_for("inventory"))
	_check(engine_texture.texture.get_size() == engine_texture.size, "普通装备继续采用原表现范围")
	var inventory := Inventory.new()
	_check(inventory.restore_items(carried).is_ok, "保持物品数量及背包坐标")
	var panel := InventoryPanel.new()
	root.add_child(panel)
	panel.position = Vector2(145, 40)
	panel.apply_inventory(inventory)
	for view: InventoryItemView in panel._item_canvas.get_children():
		var texture_size := view._icon.texture.get_size()
		var fit := minf(view._icon.size.x / texture_size.x, view._icon.size.y / texture_size.y)
		var visible_size := texture_size * fit
		_check(visible_size.x >= 20 and visible_size.y >= 20, "果实实际显示至少20px且保持比例：" + view.item.display_name)
		view.mouse_entered.emit()
		var tooltip := ItemHoverHighlight.active_tooltip() as LegacyItemTooltip
		_check(tooltip._title_label.text == view.item.display_name and tooltip._body_label.text == view.item.description,
			"实际悬浮窗显示原版文字")
		view.mouse_exited.emit()
	var bean := panel._item_canvas.get_child(1) as InventoryItemView
	bean.mouse_entered.emit()
	var tooltip := ItemHoverHighlight.active_tooltip()
	tooltip.position = panel.position + Vector2(145, 170)
	await process_frame
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/garden_items_inventory.png")
	panel.queue_free()
	tooltip.queue_free()
	await process_frame
	print("Garden item presentation: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总真实目录与渲染结果，保留每个物品的诊断信息。
## [param condition] 实际检查结果。[param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
