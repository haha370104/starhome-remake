class_name YSortedProp
extends Node2D


## 用 [param texture] 创建场景构件，将素材 [param anchor] 与 [param draw_offset] 对齐到 [param sort_baseline] 深度基线。
## Design: 父节点只承载 Y-sort 语义基线，子精灵反向补偿位置以保持原始像素坐标不变。
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
