extends SceneTree

const Hover := preload("res://scripts/client/ui/windows/item_hover_highlight.gd")
const DESCRIPTION := "新兵能量炮\n新兵必备的攻击武器之一，但是火力较小。\n需求技能等级：10\n购买价：500\n出售值：250\n重量：20\n攻击力：7\n极限攻击力：10\n功耗：10\n射程：250\n极限射程：400\n耐久：900 / 900\n双击装备"
var failures := PackedStringArray()


## 冷启动时通过真正的鼠标悬停绑定检查说明窗尺寸。
func _initialize() -> void:
	call_deferred("_run")


## 覆盖首次显示、二次显示以及长短内容切换，不等待布局后才检查首帧。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var target := Control.new()
	root.add_child(target)
	Hover.bind(target, target, DESCRIPTION)
	target.mouse_entered.emit()
	var tooltip := Hover.active_tooltip()
	var first_size := tooltip.size
	_expect(tooltip.visible, "首次悬停应立即显示")
	_expect(first_size.x == 234 and first_size.y > 150 and first_size.y < 300,
		"首次尺寸应紧贴十三行说明，实际 %s" % first_size)
	await process_frame
	await process_frame
	_expect(tooltip.size.is_equal_approx(first_size), "布局完成后不应从超大窗口跳变")
	Hover._hide_active()
	target.mouse_entered.emit()
	_expect(tooltip.size.is_equal_approx(first_size), "首次与再次悬停尺寸必须一致")
	Hover._show_tooltip(target, "短标题\n只有一行")
	_expect(tooltip.size.y < 70, "长说明切短说明应当场收缩，实际 %s" % tooltip.size)
	Hover._show_tooltip(target, DESCRIPTION)
	_expect(tooltip.size.is_equal_approx(first_size), "短说明切长说明应当场扩展至正确高度")
	Hover._show_tooltip(target, "只有标题")
	_expect(tooltip.size.y < 40, "仅标题说明不保留正文高度")
	Hover._show_tooltip(target, DESCRIPTION)
	await process_frame
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/item_tooltip_layout.png")
	target.free()
	tooltip.free()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("ITEM_TOOLTIP_LAYOUT_OK")
	quit(0 if failures.is_empty() else 1)


## 记录布局断言。
## [param condition] 必须成立的条件。
## [param message] 失败原因。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
