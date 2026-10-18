class_name EntityObstacleIndex
extends RefCounted

var positions := DeterministicSpatialGrid.new(128.0)
var targets := DeterministicSpatialGrid.new(128.0)


## 在运动批次或移动命令入口同步实体事实，避免依赖外部位置写入通知。
## [param entities] 当前地图权威实体集合。
func refresh(entities: Dictionary) -> void:
	positions.clear()
	targets.clear()
	for identity: String in entities:
		var entity: AuthoritativeEntity = entities[identity]
		positions.register(identity, entity.position)
		targets.register(identity, entity.target_position)


## 逐个实体模拟完成后更新位置，保留原顺序模拟的碰撞语义。
## [param entity] 刚完成模拟或回滚的权威实体。
func update(entity: AuthoritativeEntity) -> void:
	positions.update(entity.entity_id, entity.position)
	targets.update(entity.entity_id, entity.target_position)


## 查找位置或预留目的地与候选点相邻的实体。
## [param point] 候选点。[param radius] 避让半径。[param reserved] 是否包括目的地。
## 返回去重且稳定排序的编号。
func nearby(point: Vector2, radius: float, reserved: bool) -> Array[String]:
	var result := positions.query_circle(point, radius)
	if reserved:
		for identity: String in targets.query_circle(point, radius):
			if identity not in result: result.append(identity)
	result.sort()
	return result


## 只检查实体附近的导航格，避免对全地图每个格子遍历全部玩家。
## [param navigation] 当前导航。[param entities] 权威实体。[param excluded] 发起者。
## [param radius] 动态碰撞半径。[param from_id] 不得禁用的起点格。
## 返回本次实际禁用的格编号；调用方寻路后恢复。
func block_navigation(navigation: DiamondNavigation, entities: Dictionary, excluded: String, radius: float, from_id: int) -> Array[int]:
	var disabled: Array[int] = []
	var delta := Vector2(radius, radius)
	for identity: String in entities:
		if identity == excluded: continue
		var point: Vector2 = entities[identity].position
		var first := navigation.world_to_cell(point - delta) - Vector2i.ONE
		var last := navigation.world_to_cell(point + delta) + Vector2i.ONE
		for y in range(maxi(0, first.y), mini(navigation.grid_size.y - 1, last.y) + 1):
			for x in range(maxi(0, first.x), mini(navigation.grid_size.x - 1, last.x) + 1):
				var id := navigation.cell_id(Vector2i(x, y))
				if id == from_id or not navigation.graph.has_point(id) or navigation.graph.is_point_disabled(id): continue
				if navigation.graph.get_point_position(id).distance_squared_to(point) < radius * radius:
					navigation.graph.set_point_disabled(id, true)
					disabled.append(id)
	return disabled
