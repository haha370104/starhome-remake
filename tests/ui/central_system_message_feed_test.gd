extends SceneTree

const Feed := preload("res://scripts/ui/central_system_message_feed.gd")


## 验证系统消息按顺序停留、上浮淡出且不会互相覆盖。
func _initialize() -> void:
	var feed := Feed.new()
	root.add_child(feed)
	feed.size = Vector2(1280, 720)
	feed.configure()

	feed.show_message("你的能量炮操作技能提升到21级！")
	feed.show_message("你的驾驶操作技能提升到11级！")
	assert(feed.message_label.visible)
	assert(feed.message_label.text.contains("能量炮"))
	assert(feed.queued_message_count() == 1)
	var center_y := feed.message_label.position.y

	feed.advance(Feed.HOLD_SECONDS)
	assert(is_equal_approx(feed.message_label.position.y, center_y))
	assert(is_equal_approx(feed.message_label.modulate.a, 1.0))
	feed.advance(Feed.FLOAT_SECONDS * 0.5)
	assert(feed.message_label.position.y < center_y)
	assert(is_equal_approx(feed.message_label.modulate.a, 0.5))
	feed.advance(Feed.FLOAT_SECONDS * 0.5)
	assert(feed.message_label.text.contains("驾驶"))
	assert(feed.queued_message_count() == 0)
	assert(feed.is_presenting())
	feed.advance(Feed.HOLD_SECONDS + Feed.FLOAT_SECONDS)
	assert(not feed.message_label.visible)
	assert(not feed.is_presenting())

	print("CENTRAL_SYSTEM_MESSAGE_FEED_OK (12 assertions)")
	quit(0)
