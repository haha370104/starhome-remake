extends SceneTree

const ViewScript := preload("res://scripts/client/presentation/mining/mineral_world_view.gd")
const RepositoryScript := preload("res://scripts/content/ale_sprite_repository.gd")
const GlowShader := preload("res://scripts/client/presentation/combat/ground_loot_hover_glow.gdshader")
var checks: Array[Rect2i] = []
var failures: Array[String] = []
var assertions := 0


## 在真实渲染驱动下比较原贴图与晕染材质；不能用无 GPU 的 headless 代替像素验证。
func _initialize() -> void:
	call_deferred("_run")


## 创建七种铁矿和低级生物硅对照，逐像素验证未悬浮时 RGB 和 alpha 没有二次相乘。
func _run() -> void:
	root.size = Vector2i(1120, 540)
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var background := ColorRect.new()
	background.color = Color("947653")
	background.size = Vector2(1120, 540)
	root.add_child(background)
	RuntimeContentBootstrap.mount_default()
	var repository = RepositoryScript.new()
	_expect(repository.load_default(), "矿物资源仓库必须加载")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/minerals/mining_asset_manifest.json"))
	var animation: Dictionary = repository.load_animation(manifest.definitions.iron_ore.world_animation)
	_expect(animation.frames.size() == 7, "铁矿有七种独立样式")
	for index: int in range(7):
		var view := ViewScript.new()
		root.add_child(view)
		view.configure({"visual_variant": index, "alpha": 0.85}, {"runtime_animation": animation})
		view.position = Vector2(index * 160 + 80, 100)
		var sprite: Sprite2D = view._sprite
		_add_reference(sprite.texture, view.position + sprite.position, view.modulate)
		checks.append(Rect2i(index * 160, 0, 160, 160))
	var bio: Texture2D = load("res://assets/items/materials/low_grade_biosilicon/world_icon.png")
	var sprite := Sprite2D.new()
	sprite.texture = bio
	sprite.centered = false
	sprite.position = Vector2(70, 355)
	sprite.modulate = Color(0.8, 0.9, 1.0, 0.8)
	var material := ShaderMaterial.new()
	material.shader = GlowShader
	sprite.material = material
	root.add_child(sprite)
	_add_reference(bio, sprite.position, sprite.modulate)
	checks.append(Rect2i(50, 335, 120, 65))
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	for rect: Rect2i in checks:
		var different := 0
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				var actual := rendered.get_pixel(x, y)
				var expected := rendered.get_pixel(x, y + 160 if y < 160 else y + 90)
				if maxf(absf(actual.r - expected.r), maxf(absf(actual.g - expected.g), absf(actual.b - expected.b))) > 2.0 / 255.0:
					different += 1
		_expect(different == 0, "材质与原图应一致，区域 %s 差异像素 %d" % [rect, different])
	rendered.save_png("res://.godot/mineral_color_comparison.png")
	for failure: String in failures:
		push_error(failure)
	print("MINERAL_COLOR_RENDER_%s (%d assertions)" % ["OK" if failures.is_empty() else "FAILED", assertions])
	quit(0 if failures.is_empty() else 1)


## 添加不带材质的原图，作为同一背景与调制下的像素基准。
## [param texture] 矿物图集帧或掉落物图片。
## [param position] 待比较贴图的屏幕左上位置。
## [param tint] 节点颜色与透明度，用于验证只应用一次调制。
func _add_reference(texture: Texture2D, position: Vector2, tint: Color) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = position + Vector2(0, 160 if position.y < 160 else 90)
	sprite.modulate = tint
	root.add_child(sprite)


## 收集像素和资源断言，不在首项失败后跳过其他样式。
## [param condition] 断言成立条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
