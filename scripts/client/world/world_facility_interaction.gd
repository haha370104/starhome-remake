class_name WorldFacilityInteraction
extends Node2D

var facility_id := ""
var station_id := ""
var display_name := ""
var interaction_radius := 48.0


## 配置叠加在原地图机器素材上的无额外图像交互热点。
## [param definition] 含设施 ID、业务生产类型、名称、坐标和半径的配置。
## 返回配置是否完整。
## 设计：机器图像仍由地图语义层绘制，本节点只恢复旧 AddImgEx 的业务处理器。
func configure(definition: Dictionary) -> Error:
	facility_id = String(definition.get("facility_id", ""))
	station_id = String(definition.get("station_id", ""))
	display_name = String(definition.get("name", "生产设施"))
	interaction_radius = maxf(8.0, float(definition.get("interaction_radius", 48.0)))
	var point: Variant = definition.get("position", [])
	if facility_id.is_empty() or station_id.is_empty() or not point is Array \
			or (point as Array).size() != 2:
		return ERR_INVALID_DATA
	position = Vector2(float(point[0]), float(point[1]))
	return OK


## 判断世界坐标是否落在机器交互半径内。
## [param world_position] 鼠标对应的地图世界坐标。
## 返回是否命中。
func hit_test(world_position: Vector2) -> bool:
	return global_position.distance_to(world_position) <= interaction_radius


## 构造可复用 HUD 上下文菜单的数据。
## 返回包含生产动作的纯字典。
func get_interaction_data() -> Dictionary:
	return {
		"title": display_name,
		"body": "选择要进行的操作",
		"actions": [{"id": "manufacture", "label": "开始制作"}],
	}


## 接收与 NPC 相同的选中状态接口；设施热点没有独立高亮图层。
## [param _active] 是否处于当前交互状态。
func set_interaction_active(_active: bool) -> void:
	pass


## 为尚未由主场景消费的动作返回兜底说明。
## [param action_id] HUD 发出的动作标识。
## 返回玩家可见的简短状态。
func handle_action(action_id: String) -> String:
	return "正在使用%s" % display_name if action_id == "manufacture" else "该设施暂不支持此操作"
