extends Control

const MARKER_COLOR := Color(0.65, 1.0, 0.7, 1.0)
const HALF_EXTENT := 3.0
var _map_pixels := PackedVector2Array()


## 将启用传送点投影到小地图原图坐标；与底图一起滚动和裁剪。
## [param world_size] 当前地图世界像素尺寸。
## [param image_size] 专用小地图图片的原始尺寸。
## [param transitions] 当前地图的传送定义，同一位置的多目的地只画一个标记。
func set_transitions(
	world_size: Vector2,
	image_size: Vector2,
	transitions: Array[MapTransition],
) -> void:
	_map_pixels.clear()
	var seen := {}
	for transition: MapTransition in transitions:
		if transition == null or not transition.enabled or seen.has(transition.source_anchor):
			continue
		seen[transition.source_anchor] = true
		_map_pixels.append(transition.source_anchor / world_size * image_size)
	size = image_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


## 查询当前标记投影，用于验证地图切换与滚动时的坐标一致性。
## 返回标记中心坐标的副本，避免调用方修改绘制状态。
func marker_positions() -> PackedVector2Array:
	return _map_pixels.duplicate()


## 绘制固定七像素左右的浅绿色交叉线，不随窗口大小或小地图模式缩放。
func _draw() -> void:
	for center: Vector2 in _map_pixels:
		for diagonal: Vector2 in [Vector2(HALF_EXTENT, HALF_EXTENT), Vector2(HALF_EXTENT, -HALF_EXTENT)]:
			draw_line(center - diagonal, center + diagonal, Color(0.0, 0.12, 0.05, 0.85), 3.0, true)
			draw_line(center - diagonal, center + diagonal, MARKER_COLOR, 1.5, true)
