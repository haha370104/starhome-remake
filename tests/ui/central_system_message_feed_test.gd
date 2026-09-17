extends SceneTree

const Feed := preload("res://scripts/ui/central_system_message_feed.gd")

var failures: Array[String] = []
var checks := 0


## 在视口准备后运行消息展示与可选渲染检查。
func _initialize() -> void:
	call_deferred("_run")


## 验证立即并列展示、独立寿命、顺序、换行、缩放和连续消息清理。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var feed := Feed.new()
	root.add_child(feed)
	feed.configure()
	feed.show_message("")
	_expect(not feed.is_presenting() and not feed.is_processing(), "空消息不启动表现")
	feed.show_message("你的能量炮操作技能提升到21级！")
	var first := feed.get_child(0) as Label
	_expect(first.get_rect().get_center().is_equal_approx(Vector2(640, 360)), "首条消息无需等待渲染帧就准确居中")
	feed.advance(1.0)
	feed.show_message("你的驾驶操作技能提升到11级！")
	var second := feed.get_child(1) as Label
	_expect(is_equal_approx(second.size.y, second.get_minimum_size().y), "新增消息第一帧就使用正确换行高度")
	_expect(first.visible and second.visible, "第二条立即出现，不等待第一条")
	_expect(feed.displayed_messages() == PackedStringArray([first.text, second.text]), "语义快照保持接收顺序")
	_expect(first.position.y + first.size.y < second.position.y, "较早消息排在上面，文字不重叠")
	var original_y := first.position.y
	feed.advance(1.0)
	_expect(is_equal_approx(first.modulate.a, 0.5) and is_equal_approx(second.modulate.a, 1.0), "每条消息独立计时和淡出")
	_expect(first.position.y < original_y, "较早消息独立上浮")
	feed.advance(-1.0)
	_expect(is_equal_approx(first.modulate.a, 0.5), "非法时间步长不回退消息时钟")
	feed.advance(0.5)
	_expect(feed.get_child_count() == 1 and feed.displayed_messages() == PackedStringArray([second.text]), "旧消息到期释放，不重启新消息寿命")
	_expect(is_equal_approx(second.modulate.a, 1.0), "新消息获得完整停留时间")
	feed.advance(1.0)
	_expect(not feed.is_presenting() and not feed.is_processing() and feed.get_child_count() == 0, "全部到期后不残留节点或帧处理")
	for index in range(60):
		feed.show_message("连续系统提示 %02d" % index)
	_expect(feed.displayed_messages().size() == 60 and feed.get_child_count() == 60, "同帧60条消息全部立即加入展示，没有待播队列")
	_assert_rows(feed)
	feed.advance(100.0)
	_expect(not feed.is_presenting(), "长帧可一次清理所有过期消息，不会继续播积压消息")
	feed.show_message("一条需要在小窗口自动换行的很长系统提示，内容不能盖住另一条消息。".repeat(3))
	feed.show_message("随后发生的短消息")
	feed.set_process(false)
	root.size = Vector2i(420, 480)
	await process_frame
	await process_frame
	_assert_rows(feed)
	first = feed.get_child(0) as Label
	second = feed.get_child(1) as Label
	_expect(first.size.y > second.size.y, "狭窄视口按真实换行高度排布")
	_expect(is_equal_approx(second.position.y + second.size.y * 0.5, 240.0), "窗口缩放后最新消息重新居中")
	_expect(first.position.x >= 0.0 and first.position.x + first.size.x <= 420.0, "换行文字不横向溢出")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture(feed)
	feed.free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	print("CENTRAL_SYSTEM_MESSAGE_FEED checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 检查所有活动标签均已显示并保持不重叠的时间顺序。
## [param feed] 被验证的真实消息控件。
func _assert_rows(feed: CentralSystemMessageFeed) -> void:
	var bottom := -INF
	for child: Label in feed.get_children():
		_expect(child.visible and child.mouse_filter == Control.MOUSE_FILTER_IGNORE, "提示可见且不拦截世界点击")
		_expect(child.position.y > bottom, "消息按顺序保留独立行距")
		bottom = child.position.y + child.size.y


## 输出真实消息组件的多条同时展示画面，供视觉验收。
## [param feed] 测试中的消息组件，使用项目默认中文字体。
func _capture(feed: CentralSystemMessageFeed) -> void:
	# 独立视口始终渲染，避免隐藏或移出屏幕的原生窗口被系统暂停绘制。
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	feed.reparent(viewport)
	feed.advance(100.0)
	for message: String in ["你的能量炮操作技能提升到21级！", "你的驾驶操作技能提升到11级！",
		"获得了低级类胶 × 2", "获得了中级能量催化剂 × 1", "背包空间不足，请整理后再拾取"]:
		feed.show_message(message)
		feed.advance(0.1)
	feed.set_process(false)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var captured := viewport.get_texture().get_image()
	_expect(captured.save_png("res://.godot/system-message-stack.png") == OK, "保存真实渲染的消息列表")
	var text_pixels := 0
	for y in range(0, captured.get_height(), 4):
		for x in range(0, captured.get_width(), 4):
			var pixel := captured.get_pixel(x, y)
			if pixel.r > 0.5 and pixel.g > 0.5 and pixel.b < 0.7:
				text_pixels += 1
	_expect(text_pixels > 100, "截图中实际绘制了系统消息，不能接受空白帧")
	feed.reparent(root)
	viewport.queue_free()


## 收集消息组件断言。
## [param condition] 必须成立的条件。
## [param message] 失败定位信息。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
