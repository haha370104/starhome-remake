class_name MonsterRoutePlanner
extends RefCounted


## 使用地图导航图为怪物生成静态障碍安全的完整权威路线。
## [param navigation] 当前地图唯一的导航查询对象。
## [param monster_id] 请求路线的怪物标识，仅用于拒绝空身份。
## [param current_position] 怪物当前权威脚点。
## [param requested_position] 游荡、追击或返巢期望终点。
## 返回含实际可达终点和 AStar 路径的字典；没有路线时返回空字典。
## 设计：正式服务器与离线权威桥必须共享此入口，避免两种运行模式产生不同的怪物移动规则。
static func resolve(
	navigation,
	monster_id: String,
	current_position: Vector2,
	requested_position: Vector2,
) -> Dictionary:
	if monster_id.is_empty() or navigation == null \
		or not current_position.is_finite() or not requested_position.is_finite():
		return {}
	var authoritative_target := requested_position
	if not navigation.is_walkable(authoritative_target):
		authoritative_target = navigation.closest_reachable_position(
			current_position,
			requested_position,
		)
	if not authoritative_target.is_finite():
		return {}
	var path: PackedVector2Array = navigation.find_path(
		current_position,
		authoritative_target,
	)
	if path.size() < 2:
		return {}
	return {"target": authoritative_target, "path": path}
