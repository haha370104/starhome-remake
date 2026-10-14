extends SceneTree

var checks := 0
var failures: Array[String] = []


## 等待根节点入树后测试资源缓存、导航隔离和异步结果。
func _initialize() -> void:
	call_deferred("_run")


## 验证淘汰仅移除缓存引用、两侧导航不共享及内容包异步解码。
func _run() -> void:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var texture := ImageTexture.create_from_image(image)
	var lru := TextureLruCache.new(700)
	lru.retain("a", texture)
	lru.retain("b", texture)
	_check(lru.fetch("a") == texture, "纹理命中保持引用")
	lru.retain("c", texture)
	_check(lru.fetch("b") == null and lru.fetch("a") == texture, "按最近使用淘汰")
	_check(texture.get_width() == 8 and lru.retained_bytes <= 700, "外部引用有效且预算受控")
	var oversized := TextureLruCache.new(1)
	oversized.retain("large", texture)
	_check(oversized.fetch("large") == null, "单张超限不驻留")
	var client := MapNavigationCache.for_side(&"client")
	var server := MapNavigationCache.for_side(&"server")
	client.clear()
	server.clear()
	for index in 3:
		var file := FileAccess.open("user://nav_%d.bin" % index, FileAccess.WRITE)
		file.store_buffer(PackedByteArray([1, 1, 1, 1]))
		file.close()
	var first := client.acquire("user://nav_0.bin", Vector2i(2, 2), Vector2(48, 12))
	_check(first == client.acquire("user://nav_0.bin", Vector2i(2, 2), Vector2(48, 12)), "导航命中复用图")
	var remote := server.acquire("user://nav_0.bin", Vector2i(2, 2), Vector2(48, 12))
	_check(first != remote and first.graph != remote.graph, "客户端与服务器图隔离")
	client.acquire("user://nav_1.bin", Vector2i(2, 2), Vector2(48, 12))
	client.acquire("user://nav_2.bin", Vector2i(2, 2), Vector2(48, 12))
	_check(client.size() == 2 and first.graph.get_point_count() == 4, "导航淘汰不破坏活动场景")
	_check(first != client.acquire("user://nav_0.bin", Vector2i(2, 2), Vector2(48, 12)), "淘汰导航重新加载")
	RuntimeContentBootstrap.mount_default()
	var repository := AleSpriteRepository.new()
	_check(repository.load_default(), "保留原 ALE 索引")
	var definition := repository.resolve("pic3/equip/body/tank1.ale")
	var path := String(definition.page_paths[0])
	RuntimeTextureLoader.cache.clear()
	var queue := SpriteResourceQueue.new()
	root.add_child(queue)
	var completions: Array[String] = []
	var missing: Array[String] = []
	queue.texture_ready.connect(func(completed: String, _texture: Texture2D) -> void: completions.append(completed))
	queue.texture_failed.connect(func(failed: String) -> void: missing.append(failed))
	_check(queue.request(path) == OK and queue.request(path) == OK, "重复请求合并")
	_check(queue.request("res://missing-page.png") == OK, "失败异步报告")
	var deadline := Time.get_ticks_msec() + 10000
	while (completions.is_empty() or missing.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(completions == [path] and missing == ["res://missing-page.png"], "异步成功和失败均只回调一次")
	_check(RuntimeTextureLoader.cache.fetch(path) != null, "上传结果进入预算缓存")
	_check(not repository.load_animation("pic3/equip/body/tank1.ale").is_empty(), "原 ALE 包路径仍可消费上传结果")
	queue.queue_free()
	await process_frame
	client.clear()
	server.clear()
	print("Resource reuse: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总资源所有权和异步行为断言。
## [param condition] 实际结果。[param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
