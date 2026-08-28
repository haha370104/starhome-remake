class_name YSortedProp
extends Node2D


## 执行 `configure` 对应的模块操作。
## [param texture] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param anchor] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param draw_offset] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param sort_baseline] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：父节点只承载 Y-sort 语义基线，子精灵反向补偿位置以保持原始像素坐标不变。
func configure(
	texture: Texture2D,
	anchor: Vector2,
	draw_offset: Vector2,
	sort_baseline: float,
) -> void:
	# Y-sort compares this parent position. Moving it to the semantic baseline
	# must not move the pixels, so compensate the sprite's local Y offset.
	position = Vector2(anchor.x, sort_baseline)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = false
	sprite.position = draw_offset + Vector2(0.0, anchor.y - sort_baseline)
	add_child(sprite)
