class_name YSortedProp
extends Node2D


func configure(texture: Texture2D, draw_offset: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = false
	sprite.position = draw_offset
	add_child(sprite)
