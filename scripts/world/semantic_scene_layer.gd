class_name SemanticSceneLayer
extends Node2D


## Configures one cropped final-owner chunk at its original world position.
## [param texture] is the shared packed semantic atlas texture.
## [param atlas_region] selects this chunk from the shared atlas.
## [param pixel_offset] is the chunk's top-left coordinate in map pixels.
## [param sort_baseline] is the owning scene semantic's world Y baseline.
## Design: only this parent participates in Y-sort; the child compensates the
## baseline so changing draw order cannot move reconstructed static pixels.
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
