class_name MapProjection
extends RefCounted


## 保持地图图片比例，将其居中放入可用显示区域。
## [param image_size] 图片原始尺寸。
## [param bounds] 控件可用矩形。
## 返回等比缩放后的实际地图矩形，空尺寸返回空矩形。
static func fit(image_size: Vector2, bounds: Rect2) -> Rect2:
	if image_size.x <= 0 or image_size.y <= 0:
		return Rect2()
	var extent := image_size * minf(bounds.size.x / image_size.x, bounds.size.y / image_size.y)
	return Rect2(bounds.position + (bounds.size - extent) / 2.0, extent)


## 将地图上的点击转换为世界像素坐标；留白和无效尺寸不能产生移动意图。
## [param point] 控件局部点击位置。
## [param image_rect] 控件内图片实际矩形，允许因滚动具有负偏移。
## [param world_size] 世界像素尺寸。
## 返回世界位置；不在底图内时返回无穷向量。
static func to_world(point: Vector2, image_rect: Rect2, world_size: Vector2) -> Vector2:
	if world_size.x <= 0 or world_size.y <= 0 or not image_rect.has_area() \
			or not image_rect.has_point(point):
		return Vector2.INF
	return (point - image_rect.position) / image_rect.size * world_size
