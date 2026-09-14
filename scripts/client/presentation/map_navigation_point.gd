class_name MapNavigationPoint
extends RefCounted

var id: StringName
var label: String
var category: String
var position: Vector2
var destination: Vector2
var transition_id: StringName


## 创建纯展示目的地；不保留场景节点引用，点击时由交互层重新解析标识。
## [param key] 当前地图内稳定且带类型前缀的标识。
## [param title] 可读名称。
## [param kind] NPC、设施或传送点。
## [param location] 显示在底图与列表中的世界坐标。
## [param target] 寻路终点，传送点使用可达入口而非装饰图锚点。
## [param transition] 传送定义标识，普通目的地为空。
func _init(key: StringName, title: String, kind: String, location: Vector2,
		target: Vector2, transition: StringName = &"") -> void:
	id = key
	label = title
	category = kind
	position = location
	destination = target
	transition_id = transition


## 从活动地图创建坐标快照，包含巡逻 NPC、设施及所有启用的传送目的地。
## [param npcs] 当前存活的 NPC 表现节点。
## [param facilities] 当前设施交互节点。
## [param transitions] 当前地图传送定义。
## 返回不持有世界节点的展示数据；同址多目的地保留各自入口标识。
static func collect(npcs: Array[Node2D], facilities: Array[Node2D],
		transitions: Array[MapTransition]) -> Array[MapNavigationPoint]:
	var result: Array[MapNavigationPoint] = []
	for node: Node2D in npcs + facilities:
		var category_name := "NPC" if node in npcs else "设施"
		var data: Dictionary = node.get_interaction_data()
		result.append(MapNavigationPoint.new(StringName("%s:%s" % [category_name, node.name]),
			String(data.get("title", node.name)), category_name, node.position, node.position))
	for transition: MapTransition in transitions:
		if transition == null or not transition.enabled:
			continue
		var title := transition.label if not transition.label.is_empty() else String(transition.transition_id)
		result.append(MapNavigationPoint.new(StringName("transition:%s" % transition.transition_id),
			title, "传送点", transition.source_anchor, transition.approach_point, transition.transition_id))
	return result
