class_name NpcBase
extends MovableEntity

const DomainResult := preload("res://scripts/core/domain_result.gd")

var display_name := ""
var npc_kind := "ambient"
var interaction_body := ""
var configured_actions: Array[Dictionary] = []
var patrol_points: Array[Dictionary] = []
var patrol_index := 0


## 从 NPC 配置组装可移动、可交互的领域基类。
## [param definition] 身份、出生点、巡逻和基础交互配置。
## 返回配置完成的 NPC 或身份、坐标错误。
## 设计：子类只扩展任务、商店、兑换等业务能力；场景节点和贴图不进入领域对象。
func configure(definition: Dictionary) -> DomainResult:
	var requested_id := String(definition.get("id", ""))
	var spawn_value: Variant = definition.get("spawn", [])
	if requested_id.is_empty() or not spawn_value is Array or spawn_value.size() != 2:
		return DomainResult.failure(&"npc.invalid_definition", "npc identity and spawn are required")
	entity_id = requested_id
	position = Vector2(float(spawn_value[0]), float(spawn_value[1]))
	display_name = String(definition.get("name", entity_id))
	npc_kind = String(definition.get("kind", "ambient"))
	var interaction: Variant = definition.get("interaction", {})
	if interaction is Dictionary:
		interaction_body = String(interaction.get("body", "对方似乎暂时没有事情要交给你。"))
		var raw_actions: Variant = interaction.get("actions", [])
		if raw_actions is Array:
			for action: Variant in raw_actions:
				if action is Dictionary:
					configured_actions.append(action.duplicate(true))
	var patrol: Variant = definition.get("patrol", {})
	if patrol is Dictionary:
		movement_speed = maxf(0.0, float(patrol.get("speed", 203.0)))
	return DomainResult.ok(self)


## 设置由地图导航边界确认过的巡逻点和停留区间。
## [param resolved_points] 含 resolved_position 与 dwell 的巡逻点数组。
func set_patrol_points(resolved_points: Array[Dictionary]) -> void:
	patrol_points = resolved_points.duplicate(true)
	patrol_index = 0


## 前进到巡逻序列中的下一个点。
## 返回下一个已解析世界坐标；无巡逻点时返回当前坐标。
func advance_patrol_point() -> Vector2:
	if patrol_points.is_empty():
		return position
	patrol_index = (patrol_index + 1) % patrol_points.size()
	return patrol_points[patrol_index]["resolved_position"]


## 查询当前巡逻点配置的停留时间范围。
## 返回 `[最短秒数, 最长秒数]`。
func current_dwell_range() -> Array:
	if patrol_points.is_empty():
		return [2.0, 4.0]
	return patrol_points[patrol_index].get("dwell", [1.5, 3.5])


## 查询该类 NPC 默认提供的交互动作。
## 返回动作标识与中文标签数组。
## 设计：具体 NPC 子类可覆盖此方法声明任务、商店或兑换能力。
func default_actions() -> Array[Dictionary]:
	return [{"id": "talk", "label": "交谈"}]


## 构建交互弹层需要的数据。
## 返回 NPC 身份、正文和当前可用动作。
func interaction_data() -> Dictionary:
	return {
		"npc_id": entity_id,
		"kind": npc_kind,
		"title": display_name,
		"body": interaction_body,
		"actions": configured_actions.duplicate(true) \
			if not configured_actions.is_empty() else default_actions(),
	}


## 执行一个 NPC 业务动作。
## [param action_id] 对话弹层提交的动作标识。
## 返回可展示的结果消息。
## 设计：基类仅提供兜底；有状态业务由具体子类调用相应领域服务完成。
func handle_action(action_id: String) -> String:
	return "%s 的“%s”功能尚未接入" % [display_name, action_id]
