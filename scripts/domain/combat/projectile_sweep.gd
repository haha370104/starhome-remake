class_name ProjectileSweep
extends RefCounted


## 求有限线段第一次进入圆形受击体的交点。
## [param segment_start] 弹体本逻辑段起点。
## [param segment_end] 弹体本逻辑段终点。
## [param circle_center] 权威受击圆心。
## [param circle_radius] 权威受击半径，必须大于零。
## 返回包含 `hit`、归一化线段参数 `t` 与交点 `position` 的字典。
## 设计：服务端和客户端表现层共用同一连续碰撞公式，避免高速弹体跨帧穿透。
static func segment_circle_intersection(
	segment_start: Vector2,
	segment_end: Vector2,
	circle_center: Vector2,
	circle_radius: float,
) -> Dictionary:
	if (
		not segment_start.is_finite()
		or not segment_end.is_finite()
		or not circle_center.is_finite()
		or circle_radius <= 0.0
	):
		return {"hit": false}
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return {"hit": false}
	var relative_start := segment_start - circle_center
	var radius_squared := circle_radius * circle_radius
	if relative_start.length_squared() <= radius_squared:
		return {"hit": true, "t": 0.0, "position": segment_start}
	var half_linear := relative_start.dot(segment)
	var discriminant := half_linear * half_linear - length_squared * (
		relative_start.length_squared() - radius_squared
	)
	if discriminant < 0.0:
		return {"hit": false}
	var first_t := (-half_linear - sqrt(discriminant)) / length_squared
	if first_t < 0.0 or first_t > 1.0:
		return {"hit": false}
	return {
		"hit": true,
		"t": first_t,
		"position": segment_start + segment * first_t,
	}
