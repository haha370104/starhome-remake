class_name CorrosiveEffectController
extends Node

const MANIFEST := "res://assets/monsters/toxic_gel/shared/effects/corrosion/manifest.json"

class Flight:
	extends RefCounted
	var node: Node2D
	var sprite: Sprite2D
	var first_frame: int
	var elapsed := 0.0
	var duration: float

class Cloud:
	extends RefCounted
	var node: Sprite2D
	var target_id: String
	var elapsed := 0.0

var _world: Node2D
var _local_player: Node2D
var _local_id := ""
var _flights: Dictionary[String, Flight] = {}
var _clouds: Dictionary[String, Cloud] = {}
var _flight_textures: Array[AtlasTexture] = []
var _flight_origins: Array[Vector2] = []
var _cloud_textures: Array[AtlasTexture] = []
var _cloud_origins: Array[Vector2] = []


## 载入荣耀腐蚀专用八方向喷吐和三帧地面残留。
## [param world] 活动地图世界节点。
## 返回原图清单是否可用。
func configure(world: Node2D) -> bool:
	clear()
	_world = world
	var result := JsonConfigLoader.load_dictionary(MANIFEST)
	if not result.is_ok:
		return false
	_flight_textures.clear()
	_flight_origins.clear()
	_cloud_textures.clear()
	_cloud_origins.clear()
	_load_frames(result.value.flight, _flight_textures, _flight_origins)
	_load_frames(result.value.cloud, _cloud_textures, _cloud_origins)
	return _flight_textures.size() == 40 and _cloud_textures.size() == 3


## 根据权威开始事件播放从发射点延伸的喷吐，不把整条喷雾当作小子弹平移。
## [param event] 已去重的怪物攻击事件。
## 返回是否创建了喷吐表现。
func present(event: Dictionary) -> bool:
	var id := String(event.get("attack_id", ""))
	var origin := _point(event.get("origin"))
	var target := _point(event.get("target_position"))
	var speed := float(event.get("projectile_speed", 0))
	if id.is_empty() or _flights.has(id) or _flight_textures.size() != 40 \
			or not origin.is_finite() or not target.is_finite() or speed <= 0:
		return false
	var direction := posmod(roundi(-origin.angle_to_point(target) / (PI / 4.0)), 8)
	var flight := Flight.new()
	flight.first_frame = direction * 5
	flight.duration = maxf(0.05, origin.distance_to(target) / speed)
	flight.node = Node2D.new()
	flight.node.name = "CorrosiveSpray_" + id.replace(".", "_")
	flight.node.position = origin
	# 原图方向从东开始逆时针排列；只补足八方向量化后的夹角。
	var source_angle := -direction * PI / 4.0
	flight.node.rotation = origin.angle_to_point(target) - source_angle
	var last := flight.first_frame + 4
	var forward := Vector2.from_angle(source_angle)
	var rect := Rect2(_flight_origins[last], _flight_textures[last].get_size())
	var extent := maxf(maxf(rect.position.dot(forward), rect.end.dot(forward)),
		maxf(Vector2(rect.end.x, rect.position.y).dot(forward), Vector2(rect.position.x, rect.end.y).dot(forward)))
	flight.node.scale = Vector2.ONE * origin.distance_to(target) / maxf(1.0, extent)
	flight.sprite = Sprite2D.new()
	flight.sprite.centered = false
	flight.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	flight.node.add_child(flight.sprite)
	_world.add_child(flight.node)
	_flights[id] = flight
	_show_flight_frame(flight)
	return true


## 根据完整快照重建或移除残留，不依赖可能丢失的瞬时事件。
## [param snapshot] 当前地图的权威战斗快照。
## [param local_player] 本地预测战车锚点，仅用于平滑附着表现。
func apply_snapshot(snapshot: Dictionary, local_player: Node2D) -> void:
	_local_id = String(snapshot.get("local_entity_id", ""))
	_local_player = local_player
	var observed := {}
	for value: Variant in snapshot.get("corrosive_clouds", []):
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		var id := String(row.get("effect_id", ""))
		var point := _point(row.get("position"))
		if id.is_empty() or not point.is_finite() or _cloud_textures.size() != 3:
			continue
		observed[id] = true
		settle(id)
		var cloud: Cloud = _clouds.get(id)
		if cloud == null:
			cloud = Cloud.new()
			cloud.node = Sprite2D.new()
			cloud.node.name = "CorrosiveCloud_" + id.replace(".", "_")
			cloud.node.centered = false
			cloud.node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_world.add_child(cloud.node)
			_clouds[id] = cloud
		cloud.target_id = String(row.get("attached_actor_id", ""))
		cloud.node.z_index = 1 if not cloud.target_id.is_empty() else 0
		cloud.node.position = point
		_show_cloud_frame(cloud)
	for id: String in _clouds.keys():
		if not observed.has(id):
			_clouds[id].node.free()
			_clouds.erase(id)


## 收到实际碰撞或落空事件时立即结束对应喷吐。
## [param attack_id] 原攻击 ID；脉冲 ID 不会误删其他弹体。
func settle(attack_id: String) -> void:
	if _flights.has(attack_id):
		_flights[attack_id].node.free()
		_flights.erase(attack_id)


## 推进本地动画，附着跟随预测战车，生命期完全由权威快照控制。
## [param delta] 渲染帧秒数。
func advance(delta: float) -> void:
	for id: String in _flights.keys():
		var flight := _flights[id]
		flight.elapsed += delta
		if flight.elapsed >= flight.duration:
			settle(id)
		else:
			_show_flight_frame(flight)
	for cloud: Cloud in _clouds.values():
		cloud.elapsed += delta
		_show_cloud_frame(cloud)


## 清理切图前的全部表现，不释放外部世界和战车。
func clear() -> void:
	for flight: Flight in _flights.values():
		if is_instance_valid(flight.node):
			flight.node.free()
	for cloud: Cloud in _clouds.values():
		if is_instance_valid(cloud.node):
			cloud.node.free()
	_flights.clear()
	_clouds.clear()
	_local_player = null


## 获取当前未结束的喷吐数量。
## 返回活跃喷吐数。
func flight_count() -> int:
	return _flights.size()


## 读取规范化原图帧，保留每帧原点，不烘焙错误的固定居中偏移。
## [param definition] 来自素材清单的描述符。
## [param textures] 接收裁切纹理的有类型数组。
## [param origins] 接收原点偏移的有类型数组。
func _load_frames(definition: Dictionary, textures: Array[AtlasTexture], origins: Array[Vector2]) -> void:
	var sheet := load(String(definition.texture)) as Texture2D
	for row: Dictionary in definition.frames:
		var texture := AtlasTexture.new()
		texture.atlas = sheet
		texture.region = Rect2(float(row.rect[0]), float(row.rect[1]), float(row.rect[2]), float(row.rect[3]))
		textures.append(texture)
		origins.append(_point(row.origin))


## 选择当前方向的五帧喷吐进度。
## [param flight] 当前喷吐表现。
func _show_flight_frame(flight: Flight) -> void:
	var frame := flight.first_frame + mini(4, floori(flight.elapsed / flight.duration * 5))
	flight.sprite.texture = _flight_textures[frame]
	flight.sprite.position = _flight_origins[frame]


## 按原客户端800ms周期循环残留并更新本地附着锚点。
## [param cloud] 当前残留表现。
func _show_cloud_frame(cloud: Cloud) -> void:
	var frame := posmod(floori(cloud.elapsed / 0.8 * 3), 3)
	cloud.node.texture = _cloud_textures[frame]
	cloud.node.offset = _cloud_origins[frame]
	if not cloud.target_id.is_empty() and cloud.target_id == _local_id and is_instance_valid(_local_player):
		cloud.node.position = _world.to_local(_local_player.global_position) + Vector2(0, -16)


## 校验网络边界的二维坐标。
## [param value] 外部数组字段。
## 返回有限二维坐标或无穷哨兵。
func _point(value: Variant) -> Vector2:
	if not value is Array or value.size() != 2:
		return Vector2.INF
	return Vector2(float(value[0]), float(value[1]))
