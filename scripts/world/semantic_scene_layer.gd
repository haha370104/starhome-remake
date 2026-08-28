class_name SemanticSceneLayer
extends Node2D


## 配置并初始化 `configure` 对应的模块状态。
## [param texture] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param atlas_region] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param pixel_offset] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param sort_baseline] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数遵循所在模块的职责边界。
func configure(
	texture: Texture2D,
	atlas_region: Rect2,
	pixel_offset: Vector2,
	sort_baseline: float,
) -> void:
	# The parent alone participates in world Y-sort.  The cropped texture is
	# shifted back to its original map pixel offset, so semantic grouping never
	# changes the reconstructed static scene.
	position = Vector2(pixel_offset.x, sort_baseline)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = atlas_region
	atlas.filter_clip = true
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = atlas
	sprite.centered = false
	sprite.position = Vector2(0.0, pixel_offset.y - sort_baseline)
	add_child(sprite)
