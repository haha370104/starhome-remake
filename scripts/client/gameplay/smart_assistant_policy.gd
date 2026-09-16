class_name SmartAssistantPolicy
extends RefCounted

var enabled := false
var auto_attack := false
var gun_missile_mode := false
var auto_pickup := false
var auto_repair := false
var repair_threshold := 0.5


## 应用用户偏好；无效阈值夹紧，不能改变服务端技能和距离限制。
## [param values] 设置面板或本地配置的偏好。
func apply(values: Dictionary) -> void:
	enabled = bool(values.get("enabled", false))
	auto_attack = bool(values.get("auto_attack", false))
	gun_missile_mode = bool(values.get("gun_missile_mode", false))
	auto_pickup = bool(values.get("auto_pickup", false))
	auto_repair = bool(values.get("auto_repair", false))
	repair_threshold = clampf(float(values.get("repair_threshold", 0.5)), 0.1, 0.9)


## 序列化用户选择；开关不会增加战斗能力。
## 返回可持久化的设置副本。
func snapshot() -> Dictionary:
	return {"enabled": enabled, "auto_attack": auto_attack, "auto_pickup": auto_pickup,
		"auto_repair": auto_repair, "repair_threshold": repair_threshold, "gun_missile_mode": gun_missile_mode}


## 炮导模式只交替选择实际装配的能量炮与导弹，不自动开火或改写冷却。
## [param selected] 当前HUD动作。
## [param loadout] 当前玩家已装配的装置，背包物品不参与判断。
## 返回下一武器动作；开关关闭、装配不符或选中其他动作时为空。
func next_attack_weapon(selected: String, loadout: VehicleLoadout) -> String:
	if not enabled or not gun_missile_mode or loadout == null or selected not in ["energy_cannon", "missile"]:
		return ""
	var primary := loadout.at(1)
	var tactical := loadout.at(13)
	if primary == null or primary.primary_device_kind() != "energy_cannon" or tactical == null:
		return ""
	# 当前战术槽的导弹入口与战斗目录均只启用这一正式定义。
	if tactical.definition_id != "starter_missile":
		return ""
	return "missile" if selected == "energy_cannon" else "energy_cannon"


## 根据真实快照判断是否需要触发与 Z 相同的自维修。
## [param vehicle] 服务器战车状态。
## 返回未在维修且血量低于阈值时为真。
func needs_repair(vehicle: Dictionary) -> bool:
	return enabled and auto_repair and int(vehicle.get("health", 0)) > 0 \
		and int(vehicle.get("health", 0)) < float(vehicle.get("max_health", 1)) * repair_threshold \
		and not bool(vehicle.get("self_repair_active", false))


## 从当前快照中选择半径内最近的目标，排除死怪和无效坐标。
## [param rows] 怪物或掉落快照数组。
## [param origin] 当前本地位置。
## [param radius] 用户动作允许尝试的半径。
## [param require_alive] 是否排除生命为零的怪物。
## 返回选中行；无目标时为空。
func nearest(rows: Array, origin: Vector2, radius: float, require_alive: bool) -> Dictionary:
	var best: Dictionary = {}
	var distance := radius
	for row: Dictionary in rows:
		if require_alive and int(row.get("health", 0)) <= 0:
			continue
		var point: Array = row.get("position", [])
		if point.size() != 2:
			continue
		var candidate := Vector2(float(point[0]), float(point[1]))
		var current := origin.distance_to(candidate)
		if candidate.is_finite() and current <= distance:
			distance = current
			best = row
	return best
